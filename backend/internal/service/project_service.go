package service

import (
	"encoding/json"
	"errors"
	"fmt"
	"strings"

	"doctree-backend/internal/apperr"
	"doctree-backend/internal/dto"
	"doctree-backend/internal/model"
	"doctree-backend/internal/repository"
	"github.com/google/uuid"
)

type ProjectService struct {
	projectRepo  repository.ProjectRepository
	nodeRepo     repository.NodeRepository
	templateRepo repository.TemplateRepository
}

func NewProjectService(pr repository.ProjectRepository, nr repository.NodeRepository, tr repository.TemplateRepository) *ProjectService {
	return &ProjectService{projectRepo: pr, nodeRepo: nr, templateRepo: tr}
}

type projectTransactionRunner interface {
	RunInTransaction(func(repository.ProjectRepository, repository.NodeRepository) error) error
}

func runProjectTransaction(pr repository.ProjectRepository, nr repository.NodeRepository, fn func(repository.ProjectRepository, repository.NodeRepository) error) error {
	if runner, ok := pr.(projectTransactionRunner); ok {
		return runner.RunInTransaction(fn)
	}
	return fn(pr, nr)
}

func (s *ProjectService) Create(name, key, description, version, versionNote, templateID, createdByID string) (*model.Project, error) {
	name, key, version = strings.TrimSpace(name), strings.TrimSpace(key), strings.TrimSpace(version)
	templateID, createdByID = strings.TrimSpace(templateID), strings.TrimSpace(createdByID)
	if name == "" || key == "" || version == "" || templateID == "" || createdByID == "" {
		return nil, apperr.NewBadRequest("Name, key, version, template, and creator are required")
	}
	template, err := s.templateRepo.GetByID(templateID)
	if err != nil {
		return nil, err
	}
	if template.Status != model.TemplateStatusPublished {
		return nil, apperr.NewConflict("Projects can only use published templates")
	}
	project := &model.Project{
		Name: name, Key: key, Description: strings.TrimSpace(description), Version: version,
		VersionNote: strings.TrimSpace(versionNote), Status: model.ProjectStatusDraft,
		TemplateID: templateID, CreatedByID: createdByID,
	}
	if err := runProjectTransaction(s.projectRepo, s.nodeRepo, func(pr repository.ProjectRepository, nr repository.NodeRepository) error {
		if err := pr.Create(project); err != nil {
			return err
		}
		return createProjectRoot(nr, project, template)
	}); err != nil {
		return nil, err
	}
	return s.projectRepo.GetByID(project.ID)
}

func (s *ProjectService) GetByID(id string) (*model.Project, error) {
	if strings.TrimSpace(id) == "" {
		return nil, apperr.NewBadRequest("Project ID is required")
	}
	return s.projectRepo.GetByID(id)
}

func (s *ProjectService) ExportJSON(id string) (map[string]interface{}, error) {
	return NewNodeService(s.nodeRepo, s.templateRepo, s.projectRepo, nil).ExportJSON(id)
}

func (s *ProjectService) ExportMarkdown(id string) (string, error) {
	return NewNodeService(s.nodeRepo, s.templateRepo, s.projectRepo, nil).ExportMarkdown(id)
}

func (s *ProjectService) List(userID string, page, pageSize int) ([]model.Project, int64, error) {
	if page < 1 {
		page = 1
	}
	if pageSize < 1 {
		pageSize = 20
	}
	if pageSize > 100 {
		pageSize = 100
	}
	return s.projectRepo.List(userID, (page-1)*pageSize, pageSize)
}

func (s *ProjectService) Update(id string, req *dto.UpdateProjectRequest) (*model.Project, error) {
	if req == nil {
		return nil, apperr.ErrBadRequest
	}
	project, err := s.draftProject(id)
	if err != nil {
		return nil, err
	}
	if req.Name != nil {
		project.Name = strings.TrimSpace(*req.Name)
		if project.Name == "" {
			return nil, apperr.NewBadRequest("Project name cannot be empty")
		}
	}
	if req.Description != nil {
		project.Description = strings.TrimSpace(*req.Description)
	}
	if req.VersionNote != nil {
		project.VersionNote = strings.TrimSpace(*req.VersionNote)
	}
	if err := s.projectRepo.Update(project); err != nil {
		return nil, err
	}
	return s.projectRepo.GetByID(id)
}

func (s *ProjectService) SoftDelete(id string) error {
	if _, err := s.projectRepo.GetByID(id); err != nil {
		return err
	}
	return s.projectRepo.SoftDelete(id)
}

func (s *ProjectService) Publish(id string) (*model.Project, error) {
	project, err := s.draftProject(id)
	if err != nil {
		return nil, err
	}
	project.Status = model.ProjectStatusPublished
	if err := s.projectRepo.Update(project); err != nil {
		return nil, err
	}
	return s.projectRepo.GetByID(id)
}

func (s *ProjectService) NewVersion(id, version, versionNote string, newTemplateID *string) (*model.Project, error) {
	source, err := s.projectRepo.GetByID(id)
	if err != nil {
		return nil, err
	}
	if source.Status != model.ProjectStatusPublished {
		return nil, apperr.NewConflict("Only a published project can be versioned")
	}
	version = strings.TrimSpace(version)
	if version == "" {
		return nil, apperr.NewBadRequest("Version is required")
	}

	targetTemplateID := source.TemplateID
	if newTemplateID != nil && strings.TrimSpace(*newTemplateID) != "" {
		targetTemplateID = strings.TrimSpace(*newTemplateID)
	}
	oldTemplate, err := s.templateRepo.GetByID(source.TemplateID)
	if err != nil {
		return nil, err
	}
	newTemplate := oldTemplate
	if targetTemplateID != source.TemplateID {
		newTemplate, err = s.templateRepo.GetByID(targetTemplateID)
		if err != nil {
			return nil, err
		}
		if newTemplate.Status != model.TemplateStatusPublished {
			return nil, apperr.NewConflict("Projects can only migrate to a published template")
		}
	}

	parentID := source.ID
	created := &model.Project{
		Name: source.Name, Key: source.Key, Description: source.Description, Version: version,
		VersionNote: strings.TrimSpace(versionNote), Status: model.ProjectStatusDraft,
		TemplateID: targetTemplateID, ParentVersionID: &parentID, CreatedByID: source.CreatedByID,
	}
	err = runProjectTransaction(s.projectRepo, s.nodeRepo, func(pr repository.ProjectRepository, nr repository.NodeRepository) error {
		if err := pr.Create(created); err != nil {
			return err
		}
		if err := copyProjectNodes(nr, source.ID, created.ID); err != nil {
			return err
		}
		if targetTemplateID != source.TemplateID {
			return migrateTemplateData(created.ID, oldTemplate, newTemplate, nr)
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	return s.projectRepo.GetByID(created.ID)
}

func (s *ProjectService) MigrateTemplate(projectID, oldTemplateID, newTemplateID string) error {
	project, err := s.draftProject(projectID)
	if err != nil {
		return err
	}
	if project.TemplateID != oldTemplateID {
		return apperr.NewConflict("Project does not use the supplied source template")
	}
	oldTemplate, err := s.templateRepo.GetByID(oldTemplateID)
	if err != nil {
		return err
	}
	newTemplate, err := s.templateRepo.GetByID(newTemplateID)
	if err != nil {
		return err
	}
	if newTemplate.Status != model.TemplateStatusPublished {
		return apperr.NewConflict("Projects can only migrate to a published template")
	}
	return runProjectTransaction(s.projectRepo, s.nodeRepo, func(pr repository.ProjectRepository, nr repository.NodeRepository) error {
		if err := migrateTemplateData(projectID, oldTemplate, newTemplate, nr); err != nil {
			return err
		}
		project.TemplateID = newTemplateID
		return pr.Update(project)
	})
}

func (s *ProjectService) Import(data map[string]interface{}, createdByID string) (*model.Project, error) {
	if data == nil {
		return nil, apperr.NewBadRequest("Project import data is required")
	}
	encoded, err := json.Marshal(data)
	if err != nil {
		return nil, apperr.NewBadRequest("Invalid project import data")
	}
	var payload struct {
		Project  model.Project          `json:"project"`
		Template struct{ ID string }    `json:"template"`
		Nodes    []dto.TreeNodeResponse `json:"nodes"`
	}
	if err := json.Unmarshal(encoded, &payload); err != nil {
		return nil, apperr.NewBadRequest("Invalid project import structure")
	}
	if payload.Template.ID == "" {
		payload.Template.ID = payload.Project.TemplateID
	}
	template, err := s.templateRepo.GetByID(payload.Template.ID)
	if err != nil {
		return nil, err
	}
	if template.Status != model.TemplateStatusPublished {
		return nil, apperr.NewConflict("Projects can only use published templates")
	}
	name, key, version := strings.TrimSpace(payload.Project.Name), strings.TrimSpace(payload.Project.Key), strings.TrimSpace(payload.Project.Version)
	if name == "" || key == "" || version == "" || strings.TrimSpace(createdByID) == "" {
		return nil, apperr.NewBadRequest("Imported project requires name, key, version, and creator")
	}
	project := &model.Project{
		Name: name, Key: key, Description: payload.Project.Description, Version: version,
		VersionNote: payload.Project.VersionNote, Status: model.ProjectStatusDraft,
		TemplateID: template.ID, CreatedByID: createdByID,
	}
	err = runProjectTransaction(s.projectRepo, s.nodeRepo, func(pr repository.ProjectRepository, nr repository.NodeRepository) error {
		if err := pr.Create(project); err != nil {
			return err
		}
		if len(payload.Nodes) == 0 {
			return createProjectRoot(nr, project, template)
		}
		validTypes := make(map[string]struct{}, len(template.NodeTypes))
		for _, nodeType := range template.NodeTypes {
			validTypes[nodeType.Key] = struct{}{}
		}
		for _, root := range payload.Nodes {
			if err := importTreeNode(nr, project.ID, nil, root, validTypes); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	return s.projectRepo.GetByID(project.ID)
}

func (s *ProjectService) draftProject(id string) (*model.Project, error) {
	project, err := s.projectRepo.GetByID(id)
	if err != nil {
		return nil, err
	}
	if project.Status != model.ProjectStatusDraft {
		return nil, apperr.NewConflict("Only draft projects can be edited")
	}
	return project, nil
}

func createProjectRoot(nr repository.NodeRepository, project *model.Project, template *model.Template) error {
	rootType, err := findRootNodeType(template)
	if err != nil {
		return err
	}
	root := &model.Node{ProjectID: project.ID, NodeTypeKey: rootType.Key, Name: project.Name, SortOrder: 0}
	if err := nr.Create(root); err != nil {
		return err
	}
	for _, value := range []model.NodeFieldValue{
		{NodeID: root.ID, FieldKey: "name", Value: project.Name},
		{NodeID: root.ID, FieldKey: "key", Value: project.Key},
	} {
		fieldValue := value
		if err := nr.UpsertFieldValue(&fieldValue); err != nil {
			return err
		}
	}
	return nil
}

func findRootNodeType(template *model.Template) (*model.NodeType, error) {
	for _, rule := range template.NodeRules {
		if !rule.IsRootRule {
			continue
		}
		for index := range template.NodeTypes {
			if template.NodeTypes[index].ID == rule.ChildNodeTypeID {
				return &template.NodeTypes[index], nil
			}
		}
	}
	return nil, apperr.NewBadRequest("Template does not define a valid root node type")
}

func copyProjectNodes(nr repository.NodeRepository, sourceProjectID, targetProjectID string) error {
	nodes, err := nr.GetTree(sourceProjectID)
	if err != nil {
		return err
	}
	idMap := make(map[string]string, len(nodes))
	for _, node := range nodes {
		idMap[node.ID] = uuid.New().String()
	}
	for _, source := range nodes {
		var parentID *string
		if source.ParentID != nil {
			mapped, ok := idMap[*source.ParentID]
			if !ok {
				return fmt.Errorf("copy project nodes: parent %s not found", *source.ParentID)
			}
			parentID = &mapped
		}
		copyNode := &model.Node{
			ID: idMap[source.ID], ProjectID: targetProjectID, ParentID: parentID,
			NodeTypeKey: source.NodeTypeKey, Name: source.Name, SortOrder: source.SortOrder,
		}
		if err := nr.Create(copyNode); err != nil {
			return err
		}
		for _, sourceValue := range source.FieldValues {
			value := &model.NodeFieldValue{NodeID: copyNode.ID, FieldKey: sourceValue.FieldKey, Value: sourceValue.Value}
			if err := nr.UpsertFieldValue(value); err != nil {
				return err
			}
		}
		permissions, err := nr.ListPermissions(source.ID)
		if err != nil {
			return err
		}
		for _, sourcePermission := range permissions {
			permission := &model.NodePermission{NodeID: copyNode.ID, UserID: sourcePermission.UserID, PermissionType: sourcePermission.PermissionType}
			if err := nr.CreatePermission(permission); err != nil {
				return err
			}
		}
	}
	return nil
}

func migrateTemplateData(projectID string, oldTemplate, newTemplate *model.Template, nr repository.NodeRepository) error {
	oldTypes := make(map[string]model.NodeType, len(oldTemplate.NodeTypes))
	newTypes := make(map[string]model.NodeType, len(newTemplate.NodeTypes))
	for _, nodeType := range oldTemplate.NodeTypes {
		oldTypes[nodeType.Key] = nodeType
	}
	for _, nodeType := range newTemplate.NodeTypes {
		newTypes[nodeType.Key] = nodeType
	}

	for key := range oldTypes {
		if _, exists := newTypes[key]; exists {
			continue
		}
		nodes, err := nr.GetNodesByType(projectID, key)
		if err != nil {
			return err
		}
		for _, node := range nodes {
			if _, err := nr.GetByID(node.ID); errors.Is(err, apperr.ErrNotFound) {
				continue
			} else if err != nil {
				return err
			}
			if err := nr.SoftDeleteChildren(node.ID); err != nil {
				return err
			}
			if err := nr.SoftDelete(node.ID); err != nil {
				return err
			}
		}
	}

	for key, oldType := range oldTypes {
		newType, exists := newTypes[key]
		if !exists {
			continue
		}
		nodes, err := nr.GetNodesByType(projectID, key)
		if err != nil {
			return err
		}
		oldFields := make(map[string]model.Field, len(oldType.Fields))
		newFields := make(map[string]model.Field, len(newType.Fields))
		for _, field := range oldType.Fields {
			oldFields[field.Key] = field
		}
		for _, field := range newType.Fields {
			newFields[field.Key] = field
		}
		for fieldKey := range oldFields {
			if _, kept := newFields[fieldKey]; kept {
				continue
			}
			for _, node := range nodes {
				if err := nr.DeleteFieldValuesByFieldKey(node.ID, fieldKey); err != nil {
					return err
				}
			}
		}
		for fieldKey, newField := range newFields {
			oldField, existed := oldFields[fieldKey]
			if !existed {
				for _, node := range nodes {
					value := &model.NodeFieldValue{NodeID: node.ID, FieldKey: fieldKey, Value: newField.DefaultValue}
					if err := nr.UpsertFieldValue(value); err != nil {
						return err
					}
				}
				continue
			}
			if (newField.FieldType != model.FieldTypeSelect && newField.FieldType != model.FieldTypeMultiSelect) || oldField.Options == newField.Options {
				continue
			}
			allowed, err := optionSet(newField.Options)
			if err != nil {
				return err
			}
			for _, node := range nodes {
				for _, value := range node.FieldValues {
					if value.FieldKey == fieldKey && !fieldValueAllowed(value.Value, newField.FieldType, allowed) {
						value.Value = newField.DefaultValue
						if err := nr.UpsertFieldValue(&value); err != nil {
							return err
						}
					}
				}
			}
		}
	}
	return nil
}

func optionSet(raw string) (map[string]struct{}, error) {
	allowed := make(map[string]struct{})
	if strings.TrimSpace(raw) == "" {
		return allowed, nil
	}
	var options []interface{}
	if err := json.Unmarshal([]byte(raw), &options); err != nil {
		return nil, apperr.NewBadRequest("Template field options must be a JSON array")
	}
	for _, option := range options {
		switch value := option.(type) {
		case string:
			allowed[value] = struct{}{}
		case map[string]interface{}:
			if optionValue, ok := value["value"].(string); ok {
				allowed[optionValue] = struct{}{}
			}
		}
	}
	return allowed, nil
}

func fieldValueAllowed(value string, fieldType model.FieldType, allowed map[string]struct{}) bool {
	if value == "" {
		return true
	}
	if fieldType == model.FieldTypeSelect {
		_, ok := allowed[value]
		return ok
	}
	var selected []string
	if err := json.Unmarshal([]byte(value), &selected); err != nil {
		selected = strings.Split(value, ",")
	}
	for _, item := range selected {
		if _, ok := allowed[strings.TrimSpace(item)]; !ok {
			return false
		}
	}
	return true
}

func importTreeNode(nr repository.NodeRepository, projectID string, parentID *string, source dto.TreeNodeResponse, validTypes map[string]struct{}) error {
	if _, valid := validTypes[source.NodeTypeKey]; !valid {
		return apperr.NewBadRequest(fmt.Sprintf("Imported node type %q is not in the project template", source.NodeTypeKey))
	}
	node := &model.Node{ProjectID: projectID, ParentID: parentID, NodeTypeKey: source.NodeTypeKey, Name: source.Name, SortOrder: source.SortOrder}
	if strings.TrimSpace(node.Name) == "" {
		return apperr.NewBadRequest("Imported nodes require a name")
	}
	if err := nr.Create(node); err != nil {
		return err
	}
	for _, sourceValue := range source.FieldValues {
		value := &model.NodeFieldValue{NodeID: node.ID, FieldKey: sourceValue.FieldKey, Value: sourceValue.Value}
		if err := nr.UpsertFieldValue(value); err != nil {
			return err
		}
	}
	for _, child := range source.Children {
		parent := node.ID
		if err := importTreeNode(nr, projectID, &parent, child, validTypes); err != nil {
			return err
		}
	}
	return nil
}
