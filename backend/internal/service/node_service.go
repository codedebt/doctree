package service

import (
	"errors"
	"fmt"
	"sort"
	"strings"

	"doctree-backend/internal/apperr"
	"doctree-backend/internal/dto"
	"doctree-backend/internal/model"
	"doctree-backend/internal/repository"
)

type NodeService struct {
	nodeRepo     repository.NodeRepository
	templateRepo repository.TemplateRepository
	projectRepo  repository.ProjectRepository
	userRepo     repository.UserRepository
}

func NewNodeService(nr repository.NodeRepository, tr repository.TemplateRepository, pr repository.ProjectRepository, ur repository.UserRepository) *NodeService {
	return &NodeService{nodeRepo: nr, templateRepo: tr, projectRepo: pr, userRepo: ur}
}

func (s *NodeService) GetTree(projectID string) ([]model.Node, error) {
	if _, err := s.projectRepo.GetByID(projectID); err != nil {
		return nil, err
	}
	return s.nodeRepo.GetTree(projectID)
}

func (s *NodeService) CreateNode(projectID, parentID, nodeTypeKey, name string) (*model.Node, error) {
	project, err := s.draftProject(projectID)
	if err != nil {
		return nil, err
	}
	parentID, nodeTypeKey, name = strings.TrimSpace(parentID), strings.TrimSpace(nodeTypeKey), strings.TrimSpace(name)
	if parentID == "" || nodeTypeKey == "" || name == "" {
		return nil, apperr.NewBadRequest("Parent, node type, and name are required")
	}
	parent, err := s.nodeRepo.GetByID(parentID)
	if err != nil {
		return nil, err
	}
	if parent.ProjectID != projectID {
		return nil, apperr.ErrNotFound
	}
	template, err := s.templateRepo.GetByID(project.TemplateID)
	if err != nil {
		return nil, err
	}
	parentType, childType := findNodeTypesByKey(template.NodeTypes, parent.NodeTypeKey, nodeTypeKey)
	if parentType == nil || childType == nil {
		return nil, apperr.NewBadRequest("Parent or child node type is not defined by the project template")
	}
	var allowedRule *model.NodeRule
	for index := range template.NodeRules {
		rule := &template.NodeRules[index]
		if !rule.IsRootRule && rule.ParentNodeTypeID == parentType.ID && rule.ChildNodeTypeID == childType.ID {
			allowedRule = rule
			break
		}
	}
	if allowedRule == nil {
		return nil, apperr.NewBadRequest("This node type is not allowed under the selected parent")
	}
	if allowedRule.MaxCount > 0 {
		count, err := s.nodeRepo.GetChildrenCount(projectID, parentID, nodeTypeKey)
		if err != nil {
			return nil, err
		}
		if count >= int64(allowedRule.MaxCount) {
			return nil, apperr.NewConflict("The maximum number of children for this node type has been reached")
		}
	}
	allNodes, err := s.nodeRepo.GetTree(projectID)
	if err != nil {
		return nil, err
	}
	sortOrder := 0
	for _, existing := range allNodes {
		if existing.ParentID != nil && *existing.ParentID == parentID && existing.SortOrder >= sortOrder {
			sortOrder = existing.SortOrder + 1
		}
	}

	node := &model.Node{ProjectID: projectID, ParentID: &parentID, NodeTypeKey: nodeTypeKey, Name: name, SortOrder: sortOrder}
	err = runProjectTransaction(s.projectRepo, s.nodeRepo, func(_ repository.ProjectRepository, nr repository.NodeRepository) error {
		if err := nr.Create(node); err != nil {
			return err
		}
		for _, value := range []model.NodeFieldValue{
			{NodeID: node.ID, FieldKey: "name", Value: name},
			{NodeID: node.ID, FieldKey: "key", Value: ""},
		} {
			fieldValue := value
			if err := nr.UpsertFieldValue(&fieldValue); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	return s.nodeRepo.GetByID(node.ID)
}

func (s *NodeService) UpdateNode(nodeID string, req *dto.UpdateNodeRequest) (*model.Node, error) {
	if req == nil {
		return nil, apperr.ErrBadRequest
	}
	node, err := s.nodeRepo.GetByID(nodeID)
	if err != nil {
		return nil, err
	}
	project, err := s.draftProject(node.ProjectID)
	if err != nil {
		return nil, err
	}
	template, err := s.templateRepo.GetByID(project.TemplateID)
	if err != nil {
		return nil, err
	}
	var nodeType *model.NodeType
	for index := range template.NodeTypes {
		if template.NodeTypes[index].Key == node.NodeTypeKey {
			nodeType = &template.NodeTypes[index]
			break
		}
	}
	if nodeType == nil {
		return nil, apperr.NewBadRequest("Node type is not defined by the project template")
	}
	allowedFields := make(map[string]struct{}, len(nodeType.Fields))
	for _, field := range nodeType.Fields {
		allowedFields[field.Key] = struct{}{}
	}
	for key := range req.FieldValues {
		if _, allowed := allowedFields[key]; !allowed {
			return nil, apperr.NewBadRequest(fmt.Sprintf("Field %q is not defined for this node type", key))
		}
	}
	if req.Name != nil {
		node.Name = strings.TrimSpace(*req.Name)
		if node.Name == "" {
			return nil, apperr.NewBadRequest("Node name cannot be empty")
		}
	} else if fieldName, present := req.FieldValues["name"]; present {
		node.Name = strings.TrimSpace(fieldName)
		if node.Name == "" {
			return nil, apperr.NewBadRequest("Node name cannot be empty")
		}
	}

	err = runProjectTransaction(s.projectRepo, s.nodeRepo, func(_ repository.ProjectRepository, nr repository.NodeRepository) error {
		if err := nr.Update(node); err != nil {
			return err
		}
		for key, value := range req.FieldValues {
			fieldValue := &model.NodeFieldValue{NodeID: node.ID, FieldKey: key, Value: value}
			if err := nr.UpsertFieldValue(fieldValue); err != nil {
				return err
			}
		}
		if req.Name != nil {
			return nr.UpsertFieldValue(&model.NodeFieldValue{NodeID: node.ID, FieldKey: "name", Value: node.Name})
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	return s.nodeRepo.GetByID(node.ID)
}

func (s *NodeService) DeleteNode(nodeID string) error {
	node, err := s.nodeRepo.GetByID(nodeID)
	if err != nil {
		return err
	}
	if _, err := s.draftProject(node.ProjectID); err != nil {
		return err
	}
	return runProjectTransaction(s.projectRepo, s.nodeRepo, func(_ repository.ProjectRepository, nr repository.NodeRepository) error {
		if err := nr.SoftDeleteChildren(nodeID); err != nil {
			return err
		}
		return nr.SoftDelete(nodeID)
	})
}

func (s *NodeService) UpdateSortOrder(projectID string, ids []string) error {
	if _, err := s.draftProject(projectID); err != nil {
		return err
	}
	if len(ids) == 0 {
		return apperr.NewBadRequest("Node IDs are required")
	}
	seen := make(map[string]struct{}, len(ids))
	var parentID *string
	for _, id := range ids {
		if _, duplicate := seen[id]; duplicate {
			return apperr.NewBadRequest("Node IDs must be unique")
		}
		seen[id] = struct{}{}
		node, err := s.nodeRepo.GetByID(id)
		if err != nil {
			return err
		}
		if node.ProjectID != projectID {
			return apperr.ErrNotFound
		}
		if parentID == nil {
			parentID = node.ParentID
		} else if !sameParent(parentID, node.ParentID) {
			return apperr.NewBadRequest("Only sibling nodes can be reordered together")
		}
	}
	return s.nodeRepo.UpdateSortOrder(ids)
}

func (s *NodeService) CreatePermission(nodeID, userID, permType string) (*model.NodePermission, error) {
	userID, permType = strings.TrimSpace(userID), strings.TrimSpace(permType)
	if userID == "" {
		return nil, apperr.NewBadRequest("User ID is required")
	}
	if permType != "editor" && permType != "viewer" {
		return nil, apperr.NewBadRequest("Permission type must be editor or viewer")
	}
	if _, err := s.nodeRepo.GetByID(nodeID); err != nil {
		return nil, err
	}
	if _, err := s.userRepo.GetByID(userID); err != nil {
		if errors.Is(err, apperr.ErrNotFound) {
			return nil, apperr.NewBadRequest("User does not exist")
		}
		return nil, err
	}
	permission := &model.NodePermission{NodeID: nodeID, UserID: userID, PermissionType: permType}
	if err := s.nodeRepo.CreatePermission(permission); err != nil {
		return nil, err
	}
	return permission, nil
}

func (s *NodeService) DeletePermission(permID string) error {
	if strings.TrimSpace(permID) == "" {
		return apperr.NewBadRequest("Permission ID is required")
	}
	return s.nodeRepo.DeletePermission(permID)
}

func (s *NodeService) ListPermissions(nodeID string) ([]model.NodePermission, error) {
	if _, err := s.nodeRepo.GetByID(nodeID); err != nil {
		return nil, err
	}
	return s.nodeRepo.ListPermissions(nodeID)
}

func (s *NodeService) CheckPermission(nodeID, userID, requiredPerm string, userRole model.Role) (bool, error) {
	if userRole.AtLeast(model.RoleProjectAdmin) {
		return true, nil
	}
	if requiredPerm != "editor" && requiredPerm != "viewer" {
		return false, apperr.NewBadRequest("Required permission must be editor or viewer")
	}
	permission, err := s.nodeRepo.GetEffectivePermission(nodeID, userID)
	if errors.Is(err, apperr.ErrNotFound) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	if permission == nil {
		return false, nil
	}
	if requiredPerm == "viewer" {
		return true, nil
	}
	return permission.PermissionType == "editor", nil
}

func (s *NodeService) ExportJSON(projectID string) (map[string]interface{}, error) {
	project, err := s.projectRepo.GetByID(projectID)
	if err != nil {
		return nil, err
	}
	nodes, err := s.nodeRepo.GetTree(project.ID)
	if err != nil {
		return nil, err
	}
	template, err := s.templateRepo.GetByID(project.TemplateID)
	if err != nil {
		return nil, err
	}
	return map[string]interface{}{
		"project": project,
		"template": map[string]interface{}{
			"id": template.ID, "name": template.Name, "key": template.Key, "version": template.Version,
		},
		"nodes": dto.BuildTree(nodes),
	}, nil
}

func (s *NodeService) ExportMarkdown(projectID string) (string, error) {
	project, err := s.publishedProjectForExport(projectID)
	if err != nil {
		return "", err
	}
	nodes, err := s.nodeRepo.GetTree(project.ID)
	if err != nil {
		return "", err
	}
	template, err := s.templateRepo.GetByID(project.TemplateID)
	if err != nil {
		return "", err
	}
	typeNames := make(map[string]string, len(template.NodeTypes))
	fieldNames := make(map[string]map[string]string, len(template.NodeTypes))
	for _, nodeType := range template.NodeTypes {
		typeNames[nodeType.Key] = nodeType.Name
		fieldNames[nodeType.Key] = make(map[string]string, len(nodeType.Fields))
		for _, field := range nodeType.Fields {
			fieldNames[nodeType.Key][field.Key] = field.Name
		}
	}

	var output strings.Builder
	output.WriteString("# ")
	output.WriteString(markdownText(project.Name))
	output.WriteString("\n\n")
	tree := dto.BuildTree(nodes)
	for _, root := range tree {
		renderFieldValues(&output, root, fieldNames[root.NodeTypeKey])
		for _, child := range root.Children {
			renderMarkdownNode(&output, child, 2, typeNames, fieldNames)
		}
	}
	return strings.TrimSpace(output.String()) + "\n", nil
}

func (s *NodeService) draftProject(id string) (*model.Project, error) {
	project, err := s.projectRepo.GetByID(id)
	if err != nil {
		return nil, err
	}
	if project.Status != model.ProjectStatusDraft {
		return nil, apperr.NewConflict("Only draft projects can be edited")
	}
	return project, nil
}

func (s *NodeService) publishedProjectForExport(id string) (*model.Project, error) {
	project, err := s.projectRepo.GetByID(id)
	if err != nil {
		return nil, err
	}
	visited := make(map[string]struct{})
	for project.Status != model.ProjectStatusPublished {
		if project.ParentVersionID == nil {
			return nil, apperr.NewConflict("Markdown export requires a published project version")
		}
		if _, duplicate := visited[project.ID]; duplicate {
			return nil, fmt.Errorf("project version cycle detected")
		}
		visited[project.ID] = struct{}{}
		project, err = s.projectRepo.GetByID(*project.ParentVersionID)
		if err != nil {
			return nil, err
		}
	}
	return project, nil
}

func findNodeTypesByKey(nodeTypes []model.NodeType, parentKey, childKey string) (*model.NodeType, *model.NodeType) {
	var parent, child *model.NodeType
	for index := range nodeTypes {
		if nodeTypes[index].Key == parentKey {
			parent = &nodeTypes[index]
		}
		if nodeTypes[index].Key == childKey {
			child = &nodeTypes[index]
		}
	}
	return parent, child
}

func sameParent(left, right *string) bool {
	if left == nil || right == nil {
		return left == nil && right == nil
	}
	return *left == *right
}

func renderMarkdownNode(output *strings.Builder, node dto.TreeNodeResponse, depth int, typeNames map[string]string, fieldNames map[string]map[string]string) {
	if depth > 6 {
		depth = 6
	}
	output.WriteString(strings.Repeat("#", depth))
	output.WriteString(" ")
	if typeName := typeNames[node.NodeTypeKey]; typeName != "" {
		output.WriteString(markdownText(typeName))
		output.WriteString(": ")
	}
	output.WriteString(markdownText(node.Name))
	output.WriteString("\n\n")
	renderFieldValues(output, node, fieldNames[node.NodeTypeKey])
	for _, child := range node.Children {
		renderMarkdownNode(output, child, depth+1, typeNames, fieldNames)
	}
}

func renderFieldValues(output *strings.Builder, node dto.TreeNodeResponse, names map[string]string) {
	values := append([]model.NodeFieldValue(nil), node.FieldValues...)
	sort.SliceStable(values, func(i, j int) bool { return values[i].CreatedAt.Before(values[j].CreatedAt) })
	for _, value := range values {
		if value.FieldKey == "name" || strings.TrimSpace(value.Value) == "" {
			continue
		}
		label := names[value.FieldKey]
		if label == "" {
			label = value.FieldKey
		}
		output.WriteString("- ")
		output.WriteString(markdownText(label))
		output.WriteString(": ")
		output.WriteString(markdownText(value.Value))
		output.WriteString("\n")
	}
	if len(values) > 0 {
		output.WriteString("\n")
	}
}

func markdownText(value string) string {
	value = strings.ReplaceAll(value, "\r", " ")
	value = strings.ReplaceAll(value, "\n", " ")
	return strings.TrimSpace(value)
}
