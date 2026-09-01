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
)

type TemplateService struct {
	repo repository.TemplateRepository
}

type templateStatusUpdater interface {
	UpdateStatus(id string, status model.TemplateStatus) error
}

func NewTemplateService(repo repository.TemplateRepository) *TemplateService {
	return &TemplateService{repo: repo}
}

func (s *TemplateService) Create(name, key, version, versionNote, createdByID string) (*model.Template, error) {
	name, key, version = strings.TrimSpace(name), strings.TrimSpace(key), strings.TrimSpace(version)
	if name == "" || key == "" || version == "" || strings.TrimSpace(createdByID) == "" {
		return nil, apperr.NewBadRequest("Name, key, version, and creator are required")
	}
	if _, err := s.repo.GetByKeyAndVersion(key, version); err == nil {
		return nil, apperr.NewConflict("A template with this key and version already exists")
	} else if !errors.Is(err, apperr.ErrNotFound) {
		return nil, err
	}

	template := &model.Template{
		Name:        name,
		Key:         key,
		Version:     version,
		VersionNote: strings.TrimSpace(versionNote),
		Status:      model.TemplateStatusDraft,
		CreatedByID: createdByID,
	}
	if err := s.repo.Create(template); err != nil {
		return nil, err
	}
	return template, nil
}

func (s *TemplateService) GetByID(id string) (*model.Template, error) {
	if strings.TrimSpace(id) == "" {
		return nil, apperr.NewBadRequest("Template ID is required")
	}
	return s.repo.GetByID(id)
}

func (s *TemplateService) List(status string, page, pageSize int) ([]model.Template, int64, error) {
	if page < 1 {
		page = 1
	}
	if pageSize < 1 {
		pageSize = 20
	}
	if pageSize > 100 {
		pageSize = 100
	}
	if status != "" && status != string(model.TemplateStatusDraft) && status != string(model.TemplateStatusPublished) {
		return nil, 0, apperr.NewBadRequest("Invalid template status")
	}
	return s.repo.List(status, (page-1)*pageSize, pageSize)
}

func (s *TemplateService) Update(id string, req *dto.UpdateTemplateRequest) (*model.Template, error) {
	if req == nil {
		return nil, apperr.ErrBadRequest
	}
	template, err := s.draftTemplate(id)
	if err != nil {
		return nil, err
	}
	if req.Name != nil {
		template.Name = strings.TrimSpace(*req.Name)
		if template.Name == "" {
			return nil, apperr.NewBadRequest("Template name cannot be empty")
		}
	}
	if req.VersionNote != nil {
		template.VersionNote = strings.TrimSpace(*req.VersionNote)
	}
	if err := s.repo.Update(template); err != nil {
		return nil, err
	}
	return s.repo.GetByID(id)
}

func (s *TemplateService) SoftDelete(id string) error {
	if _, err := s.repo.GetByID(id); err != nil {
		return err
	}
	return s.repo.SoftDelete(id)
}

func (s *TemplateService) Publish(id string) (*model.Template, error) {
	template, err := s.draftTemplate(id)
	if err != nil {
		return nil, err
	}
	if len(template.NodeTypes) == 0 {
		return nil, apperr.NewBadRequest("A template must contain at least one node type")
	}

	nodeTypeIDs := make(map[string]struct{}, len(template.NodeTypes))
	for _, nt := range template.NodeTypes {
		nodeTypeIDs[nt.ID] = struct{}{}
		fieldKeys := make(map[string]struct{}, len(nt.Fields))
		for _, field := range nt.Fields {
			fieldKeys[field.Key] = struct{}{}
		}
		if _, ok := fieldKeys["name"]; !ok {
			return nil, apperr.NewBadRequest(fmt.Sprintf("Node type %q is missing the name field", nt.Name))
		}
		if _, ok := fieldKeys["key"]; !ok {
			return nil, apperr.NewBadRequest(fmt.Sprintf("Node type %q is missing the key field", nt.Name))
		}
	}

	hasRootRule := false
	for _, rule := range template.NodeRules {
		if _, ok := nodeTypeIDs[rule.ChildNodeTypeID]; !ok {
			return nil, apperr.NewBadRequest("A rule references an unknown child node type")
		}
		if rule.ParentNodeTypeID != "" {
			if _, ok := nodeTypeIDs[rule.ParentNodeTypeID]; !ok {
				return nil, apperr.NewBadRequest("A rule references an unknown parent node type")
			}
		} else if !rule.IsRootRule {
			return nil, apperr.NewBadRequest("A non-root rule must reference a parent node type")
		}
		if rule.IsRootRule {
			hasRootRule = true
		}
	}
	if !hasRootRule {
		return nil, apperr.NewBadRequest("A template must contain at least one root rule")
	}

	updater, ok := s.repo.(templateStatusUpdater)
	if !ok {
		return nil, fmt.Errorf("template repository does not support status updates")
	}
	if err := updater.UpdateStatus(id, model.TemplateStatusPublished); err != nil {
		return nil, err
	}
	return s.repo.GetByID(id)
}

func (s *TemplateService) NewVersion(id, version, versionNote string) (*model.Template, error) {
	source, err := s.repo.GetByID(id)
	if err != nil {
		return nil, err
	}
	if source.Status != model.TemplateStatusPublished {
		return nil, apperr.NewBadRequest("Only a published template can be versioned")
	}
	version = strings.TrimSpace(version)
	if version == "" {
		return nil, apperr.NewBadRequest("Version is required")
	}
	if _, err := s.repo.GetByKeyAndVersion(source.Key, version); err == nil {
		return nil, apperr.NewConflict("A template with this key and version already exists")
	} else if !errors.Is(err, apperr.ErrNotFound) {
		return nil, err
	}

	parentID := source.ID
	copyTemplate := &model.Template{
		Name:            source.Name,
		Key:             source.Key,
		Version:         version,
		VersionNote:     strings.TrimSpace(versionNote),
		Status:          model.TemplateStatusDraft,
		ParentVersionID: &parentID,
		CreatedByID:     source.CreatedByID,
	}
	if err := s.repo.Create(copyTemplate); err != nil {
		return nil, err
	}
	if err := s.copyStructure(copyTemplate.ID, source.NodeTypes, source.NodeRules); err != nil {
		_ = s.repo.SoftDelete(copyTemplate.ID)
		return nil, err
	}
	return s.repo.GetByID(copyTemplate.ID)
}

func (s *TemplateService) CreateNodeType(templateID string, req *dto.CreateNodeTypeRequest) (*model.NodeType, error) {
	if req == nil {
		return nil, apperr.ErrBadRequest
	}
	if _, err := s.draftTemplate(templateID); err != nil {
		return nil, err
	}
	name, key := strings.TrimSpace(req.Name), strings.TrimSpace(req.Key)
	if name == "" || key == "" {
		return nil, apperr.NewBadRequest("Node type name and key are required")
	}
	nodeTypes, err := s.repo.ListNodeTypes(templateID)
	if err != nil {
		return nil, err
	}
	for _, existing := range nodeTypes {
		if existing.Key == key {
			return nil, apperr.NewConflict("A node type with this key already exists")
		}
	}
	nt := &model.NodeType{TemplateID: templateID, Name: name, Key: key, Description: strings.TrimSpace(req.Description), SortOrder: len(nodeTypes)}
	if err := s.repo.CreateNodeType(nt); err != nil {
		return nil, err
	}
	return s.repo.GetNodeTypeByID(nt.ID)
}

func (s *TemplateService) UpdateNodeType(templateID, nodeTypeID string, req *dto.UpdateNodeTypeRequest) (*model.NodeType, error) {
	if req == nil {
		return nil, apperr.ErrBadRequest
	}
	if _, err := s.draftTemplate(templateID); err != nil {
		return nil, err
	}
	nt, err := s.nodeTypeInTemplate(templateID, nodeTypeID)
	if err != nil {
		return nil, err
	}
	if req.Name != nil {
		nt.Name = strings.TrimSpace(*req.Name)
		if nt.Name == "" {
			return nil, apperr.NewBadRequest("Node type name cannot be empty")
		}
	}
	if req.Key != nil {
		newKey := strings.TrimSpace(*req.Key)
		if newKey == "" {
			return nil, apperr.NewBadRequest("Node type key cannot be empty")
		}
		nodeTypes, listErr := s.repo.ListNodeTypes(templateID)
		if listErr != nil {
			return nil, listErr
		}
		for _, existing := range nodeTypes {
			if existing.ID != nodeTypeID && existing.Key == newKey {
				return nil, apperr.NewConflict("A node type with this key already exists")
			}
		}
		nt.Key = newKey
	}
	if req.Description != nil {
		nt.Description = strings.TrimSpace(*req.Description)
	}
	if err := s.repo.UpdateNodeType(nt); err != nil {
		return nil, err
	}
	return s.repo.GetNodeTypeByID(nodeTypeID)
}

func (s *TemplateService) DeleteNodeType(templateID, nodeTypeID string) error {
	if _, err := s.draftTemplate(templateID); err != nil {
		return err
	}
	if _, err := s.nodeTypeInTemplate(templateID, nodeTypeID); err != nil {
		return err
	}
	rules, err := s.repo.ListNodeRules(templateID)
	if err != nil {
		return err
	}
	for _, rule := range rules {
		if rule.ParentNodeTypeID == nodeTypeID || rule.ChildNodeTypeID == nodeTypeID {
			return apperr.NewConflict("Delete rules that reference this node type first")
		}
	}
	return s.repo.DeleteNodeType(nodeTypeID)
}

func (s *TemplateService) UpdateNodeTypeSortOrder(templateID string, ids []string) error {
	if _, err := s.draftTemplate(templateID); err != nil {
		return err
	}
	nodeTypes, err := s.repo.ListNodeTypes(templateID)
	if err != nil {
		return err
	}
	if err := validateSortIDs(ids, len(nodeTypes), func(id string) bool {
		for _, nt := range nodeTypes {
			if nt.ID == id {
				return true
			}
		}
		return false
	}); err != nil {
		return err
	}
	return s.repo.UpdateNodeTypeSortOrder(ids)
}

func (s *TemplateService) ListNodeTypes(templateID string) ([]model.NodeType, error) {
	if _, err := s.repo.GetByID(templateID); err != nil {
		return nil, err
	}
	return s.repo.ListNodeTypes(templateID)
}

func (s *TemplateService) CreateField(templateID, nodeTypeID string, req *dto.CreateFieldRequest) (*model.Field, error) {
	if req == nil {
		return nil, apperr.ErrBadRequest
	}
	if _, err := s.draftTemplate(templateID); err != nil {
		return nil, err
	}
	nt, err := s.nodeTypeInTemplate(templateID, nodeTypeID)
	if err != nil {
		return nil, err
	}
	fieldType := model.FieldType(req.FieldType)
	if err := validateField(req.Name, req.Key, fieldType, req.Options); err != nil {
		return nil, err
	}
	for _, existing := range nt.Fields {
		if existing.Key == strings.TrimSpace(req.Key) {
			return nil, apperr.NewConflict("A field with this key already exists")
		}
	}
	field := &model.Field{
		NodeTypeID: nt.ID, Name: strings.TrimSpace(req.Name), Key: strings.TrimSpace(req.Key),
		FieldType: fieldType, Required: req.Required, DefaultValue: req.DefaultValue,
		Description: strings.TrimSpace(req.Description), Options: req.Options,
		SortOrder: len(nt.Fields), Deletable: true,
	}
	if err := s.repo.CreateField(field); err != nil {
		return nil, err
	}
	return field, nil
}

func (s *TemplateService) UpdateField(templateID, nodeTypeID, fieldID string, req *dto.UpdateFieldRequest) (*model.Field, error) {
	if req == nil {
		return nil, apperr.ErrBadRequest
	}
	if _, err := s.draftTemplate(templateID); err != nil {
		return nil, err
	}
	nt, err := s.nodeTypeInTemplate(templateID, nodeTypeID)
	if err != nil {
		return nil, err
	}
	field, err := s.fieldInNodeType(nodeTypeID, fieldID)
	if err != nil {
		return nil, err
	}
	if req.Name != nil {
		field.Name = strings.TrimSpace(*req.Name)
	}
	if req.Key != nil {
		field.Key = strings.TrimSpace(*req.Key)
	}
	if req.FieldType != nil {
		field.FieldType = model.FieldType(*req.FieldType)
	}
	if req.Required != nil {
		field.Required = *req.Required
	}
	if req.DefaultValue != nil {
		field.DefaultValue = *req.DefaultValue
	}
	if req.Description != nil {
		field.Description = strings.TrimSpace(*req.Description)
	}
	if req.Options != nil {
		field.Options = *req.Options
	}
	if err := validateField(field.Name, field.Key, field.FieldType, field.Options); err != nil {
		return nil, err
	}
	for _, existing := range nt.Fields {
		if existing.ID != fieldID && existing.Key == field.Key {
			return nil, apperr.NewConflict("A field with this key already exists")
		}
	}
	if err := s.repo.UpdateField(field); err != nil {
		return nil, err
	}
	return s.repo.GetFieldByID(fieldID)
}

func (s *TemplateService) DeleteField(templateID, nodeTypeID, fieldID string) error {
	if _, err := s.draftTemplate(templateID); err != nil {
		return err
	}
	field, err := s.fieldInNodeType(nodeTypeID, fieldID)
	if err != nil {
		return err
	}
	if !field.Deletable {
		return apperr.NewBadRequest("This field cannot be deleted")
	}
	return s.repo.DeleteField(fieldID)
}

func (s *TemplateService) UpdateFieldSortOrder(templateID, nodeTypeID string, ids []string) error {
	if _, err := s.draftTemplate(templateID); err != nil {
		return err
	}
	nt, err := s.nodeTypeInTemplate(templateID, nodeTypeID)
	if err != nil {
		return err
	}
	if err := validateSortIDs(ids, len(nt.Fields), func(id string) bool {
		for _, field := range nt.Fields {
			if field.ID == id {
				return true
			}
		}
		return false
	}); err != nil {
		return err
	}
	return s.repo.UpdateFieldSortOrder(ids)
}

func (s *TemplateService) CreateNodeRule(templateID string, req *dto.CreateNodeRuleRequest) (*model.NodeRule, error) {
	if req == nil {
		return nil, apperr.ErrBadRequest
	}
	if _, err := s.draftTemplate(templateID); err != nil {
		return nil, err
	}
	if err := s.validateRule(templateID, req.ParentNodeTypeID, req.ChildNodeTypeID, req.MinCount, req.MaxCount, req.IsRootRule); err != nil {
		return nil, err
	}
	rule := &model.NodeRule{
		TemplateID: templateID, ParentNodeTypeID: req.ParentNodeTypeID, ChildNodeTypeID: req.ChildNodeTypeID,
		MinCount: req.MinCount, MaxCount: req.MaxCount, IsRootRule: req.IsRootRule,
	}
	if err := s.repo.CreateNodeRule(rule); err != nil {
		return nil, err
	}
	return rule, nil
}

func (s *TemplateService) UpdateNodeRule(templateID, ruleID string, req *dto.UpdateNodeRuleRequest) (*model.NodeRule, error) {
	if req == nil {
		return nil, apperr.ErrBadRequest
	}
	if _, err := s.draftTemplate(templateID); err != nil {
		return nil, err
	}
	rule, err := s.ruleInTemplate(templateID, ruleID)
	if err != nil {
		return nil, err
	}
	if req.ChildNodeTypeID != nil {
		rule.ChildNodeTypeID = *req.ChildNodeTypeID
	}
	if req.MinCount != nil {
		rule.MinCount = *req.MinCount
	}
	if req.MaxCount != nil {
		rule.MaxCount = *req.MaxCount
	}
	if err := s.validateRule(templateID, rule.ParentNodeTypeID, rule.ChildNodeTypeID, rule.MinCount, rule.MaxCount, rule.IsRootRule); err != nil {
		return nil, err
	}
	if err := s.repo.UpdateNodeRule(rule); err != nil {
		return nil, err
	}
	return s.repo.GetNodeRuleByID(ruleID)
}

func (s *TemplateService) DeleteNodeRule(templateID, ruleID string) error {
	if _, err := s.draftTemplate(templateID); err != nil {
		return err
	}
	if _, err := s.ruleInTemplate(templateID, ruleID); err != nil {
		return err
	}
	return s.repo.DeleteNodeRule(ruleID)
}

func (s *TemplateService) ListNodeRules(templateID string) ([]model.NodeRule, error) {
	if _, err := s.repo.GetByID(templateID); err != nil {
		return nil, err
	}
	return s.repo.ListNodeRules(templateID)
}

func (s *TemplateService) Export(id string) (map[string]interface{}, error) {
	template, err := s.repo.GetByID(id)
	if err != nil {
		return nil, err
	}
	encoded, err := json.Marshal(template)
	if err != nil {
		return nil, err
	}
	var result map[string]interface{}
	if err := json.Unmarshal(encoded, &result); err != nil {
		return nil, err
	}
	return result, nil
}

func (s *TemplateService) Import(data map[string]interface{}, createdByID string) (*model.Template, error) {
	if data == nil {
		return nil, apperr.NewBadRequest("Template import data is required")
	}
	encoded, err := json.Marshal(data)
	if err != nil {
		return nil, apperr.NewBadRequest("Invalid template import data")
	}
	var source model.Template
	if err := json.Unmarshal(encoded, &source); err != nil {
		return nil, apperr.NewBadRequest("Invalid template import structure")
	}
	created, err := s.Create(source.Name, source.Key, source.Version, source.VersionNote, createdByID)
	if err != nil {
		return nil, err
	}
	if err := s.copyStructure(created.ID, source.NodeTypes, source.NodeRules); err != nil {
		_ = s.repo.SoftDelete(created.ID)
		return nil, err
	}
	return s.repo.GetByID(created.ID)
}

func (s *TemplateService) draftTemplate(id string) (*model.Template, error) {
	template, err := s.repo.GetByID(id)
	if err != nil {
		return nil, err
	}
	if template.Status != model.TemplateStatusDraft {
		return nil, apperr.NewConflict("Only draft templates can be edited")
	}
	return template, nil
}

func (s *TemplateService) nodeTypeInTemplate(templateID, nodeTypeID string) (*model.NodeType, error) {
	nt, err := s.repo.GetNodeTypeByID(nodeTypeID)
	if err != nil {
		return nil, err
	}
	if nt.TemplateID != templateID {
		return nil, apperr.ErrNotFound
	}
	return nt, nil
}

func (s *TemplateService) fieldInNodeType(nodeTypeID, fieldID string) (*model.Field, error) {
	field, err := s.repo.GetFieldByID(fieldID)
	if err != nil {
		return nil, err
	}
	if field.NodeTypeID != nodeTypeID {
		return nil, apperr.ErrNotFound
	}
	return field, nil
}

func (s *TemplateService) ruleInTemplate(templateID, ruleID string) (*model.NodeRule, error) {
	rule, err := s.repo.GetNodeRuleByID(ruleID)
	if err != nil {
		return nil, err
	}
	if rule.TemplateID != templateID {
		return nil, apperr.ErrNotFound
	}
	return rule, nil
}

func (s *TemplateService) validateRule(templateID, parentID, childID string, minCount, maxCount int, isRoot bool) error {
	if childID == "" {
		return apperr.NewBadRequest("Child node type is required")
	}
	if minCount < 0 || maxCount < 0 || (maxCount != 0 && maxCount < minCount) {
		return apperr.NewBadRequest("Rule counts are invalid")
	}
	if _, err := s.nodeTypeInTemplate(templateID, childID); err != nil {
		return apperr.NewBadRequest("Child node type does not belong to this template")
	}
	if parentID == "" {
		if !isRoot {
			return apperr.NewBadRequest("Parent node type is required for a non-root rule")
		}
		return nil
	}
	if _, err := s.nodeTypeInTemplate(templateID, parentID); err != nil {
		return apperr.NewBadRequest("Parent node type does not belong to this template")
	}
	return nil
}

func (s *TemplateService) copyStructure(templateID string, sourceNodeTypes []model.NodeType, sourceRules []model.NodeRule) error {
	oldToNew := make(map[string]string, len(sourceNodeTypes))
	newByKey := make(map[string]string, len(sourceNodeTypes))
	nodeTypeIDs := make([]string, 0, len(sourceNodeTypes))

	for index, sourceNT := range sourceNodeTypes {
		if strings.TrimSpace(sourceNT.Name) == "" || strings.TrimSpace(sourceNT.Key) == "" {
			return apperr.NewBadRequest("Imported node types require name and key")
		}
		if _, duplicate := newByKey[sourceNT.Key]; duplicate {
			return apperr.NewBadRequest("Imported node type keys must be unique")
		}
		newNT := &model.NodeType{TemplateID: templateID, Name: sourceNT.Name, Key: sourceNT.Key, Description: sourceNT.Description, SortOrder: index}
		if err := s.repo.CreateNodeType(newNT); err != nil {
			return err
		}
		oldToNew[sourceNT.ID] = newNT.ID
		newByKey[sourceNT.Key] = newNT.ID
		nodeTypeIDs = append(nodeTypeIDs, newNT.ID)
		if err := s.copyFields(newNT.ID, sourceNT.Fields); err != nil {
			return err
		}
	}
	if len(nodeTypeIDs) > 0 {
		if err := s.repo.UpdateNodeTypeSortOrder(nodeTypeIDs); err != nil {
			return err
		}
	}

	for _, sourceRule := range sourceRules {
		childID := oldToNew[sourceRule.ChildNodeTypeID]
		parentID := ""
		if sourceRule.ParentNodeTypeID != "" {
			parentID = oldToNew[sourceRule.ParentNodeTypeID]
		}
		if childID == "" || (sourceRule.ParentNodeTypeID != "" && parentID == "") {
			return apperr.NewBadRequest("Imported rule references an unknown node type")
		}
		if err := s.validateRule(templateID, parentID, childID, sourceRule.MinCount, sourceRule.MaxCount, sourceRule.IsRootRule); err != nil {
			return err
		}
		newRule := &model.NodeRule{
			TemplateID: templateID, ParentNodeTypeID: parentID, ChildNodeTypeID: childID,
			MinCount: sourceRule.MinCount, MaxCount: sourceRule.MaxCount, IsRootRule: sourceRule.IsRootRule,
		}
		if err := s.repo.CreateNodeRule(newRule); err != nil {
			return err
		}
	}
	return nil
}

func (s *TemplateService) copyFields(nodeTypeID string, sourceFields []model.Field) error {
	createdNT, err := s.repo.GetNodeTypeByID(nodeTypeID)
	if err != nil {
		return err
	}
	generatedByKey := make(map[string]*model.Field, len(createdNT.Fields))
	for index := range createdNT.Fields {
		generatedByKey[createdNT.Fields[index].Key] = &createdNT.Fields[index]
	}
	seenKeys := make(map[string]struct{}, len(sourceFields))
	orderedIDs := make([]string, 0, len(sourceFields))
	for _, sourceField := range sourceFields {
		if _, duplicate := seenKeys[sourceField.Key]; duplicate {
			return apperr.NewBadRequest("Imported field keys must be unique within a node type")
		}
		seenKeys[sourceField.Key] = struct{}{}
		if err := validateField(sourceField.Name, sourceField.Key, sourceField.FieldType, sourceField.Options); err != nil {
			return err
		}
		if generated := generatedByKey[sourceField.Key]; generated != nil {
			generated.Name = sourceField.Name
			generated.FieldType = sourceField.FieldType
			generated.Required = sourceField.Required
			generated.DefaultValue = sourceField.DefaultValue
			generated.Description = sourceField.Description
			generated.Options = sourceField.Options
			if err := s.repo.UpdateField(generated); err != nil {
				return err
			}
			orderedIDs = append(orderedIDs, generated.ID)
			continue
		}
		newField := &model.Field{
			NodeTypeID: nodeTypeID, Name: sourceField.Name, Key: sourceField.Key, FieldType: sourceField.FieldType,
			Required: sourceField.Required, DefaultValue: sourceField.DefaultValue, Description: sourceField.Description,
			Options: sourceField.Options, SortOrder: len(orderedIDs), Deletable: sourceField.Deletable,
		}
		if err := s.repo.CreateField(newField); err != nil {
			return err
		}
		orderedIDs = append(orderedIDs, newField.ID)
	}
	for _, generated := range createdNT.Fields {
		if _, keep := seenKeys[generated.Key]; !keep {
			if !generated.Deletable {
				return apperr.NewBadRequest(fmt.Sprintf("Imported node type is missing required field %q", generated.Key))
			}
			if err := s.repo.DeleteField(generated.ID); err != nil {
				return err
			}
		}
	}
	if len(orderedIDs) > 0 {
		return s.repo.UpdateFieldSortOrder(orderedIDs)
	}
	return nil
}

func validateField(name, key string, fieldType model.FieldType, options string) error {
	if strings.TrimSpace(name) == "" || strings.TrimSpace(key) == "" {
		return apperr.NewBadRequest("Field name and key are required")
	}
	switch fieldType {
	case model.FieldTypeText, model.FieldTypeTextarea, model.FieldTypeSelect, model.FieldTypeMultiSelect, model.FieldTypeCheckbox, model.FieldTypeDate:
	default:
		return apperr.NewBadRequest("Invalid field type")
	}
	if options != "" {
		var values []interface{}
		if err := json.Unmarshal([]byte(options), &values); err != nil {
			return apperr.NewBadRequest("Field options must be a JSON array string")
		}
	}
	return nil
}

func validateSortIDs(ids []string, expected int, belongs func(string) bool) error {
	if len(ids) != expected {
		return apperr.NewBadRequest("Sort request must include every item exactly once")
	}
	seen := make(map[string]struct{}, len(ids))
	for _, id := range ids {
		if _, duplicate := seen[id]; duplicate || !belongs(id) {
			return apperr.NewBadRequest("Sort request contains duplicate or unknown IDs")
		}
		seen[id] = struct{}{}
	}
	return nil
}
