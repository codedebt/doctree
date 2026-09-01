package repository

import (
	"errors"
	"fmt"
	"time"

	"doctree-backend/internal/apperr"
	"doctree-backend/internal/model"
	"github.com/google/uuid"
	"gorm.io/gorm"
)

type templateRepository struct {
	db *gorm.DB
}

func NewTemplateRepository(db *gorm.DB) TemplateRepository {
	return &templateRepository{db: db}
}

func (r *templateRepository) Create(template *model.Template) error {
	if template.ID == "" {
		template.ID = uuid.New().String()
	}
	if template.CreatedAt.IsZero() {
		template.CreatedAt = time.Now().UTC()
	}
	return r.db.Create(template).Error
}

func (r *templateRepository) GetByID(id string) (*model.Template, error) {
	var template model.Template
	err := r.db.
		Where("templates.id = ? AND templates.deleted_at IS NULL AND templates.status <> ?", id, model.TemplateStatusDeleted).
		Preload("NodeTypes", func(db *gorm.DB) *gorm.DB { return db.Order("sort_order ASC") }).
		Preload("NodeTypes.Fields", func(db *gorm.DB) *gorm.DB { return db.Order("sort_order ASC") }).
		Preload("NodeRules", func(db *gorm.DB) *gorm.DB { return db.Order("created_at ASC") }).
		First(&template).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, apperr.ErrNotFound
	}
	return &template, err
}

func (r *templateRepository) List(status string, offset, limit int) ([]model.Template, int64, error) {
	query := r.db.Model(&model.Template{}).
		Where("deleted_at IS NULL AND status <> ?", model.TemplateStatusDeleted)
	if status != "" {
		query = query.Where("status = ?", status)
	}

	var total int64
	if err := query.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	var templates []model.Template
	if err := query.Order("created_at DESC").Offset(offset).Limit(limit).Find(&templates).Error; err != nil {
		return nil, 0, err
	}
	return templates, total, nil
}

func (r *templateRepository) Update(template *model.Template) error {
	result := r.db.Model(&model.Template{}).
		Where("id = ? AND deleted_at IS NULL", template.ID).
		Updates(map[string]interface{}{
			"name":         template.Name,
			"version_note": template.VersionNote,
		})
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected == 0 {
		return apperr.ErrNotFound
	}
	return nil
}

// UpdateStatus is intentionally not part of TemplateRepository's public editing API.
// It is used by the service only after publish validation has succeeded.
func (r *templateRepository) UpdateStatus(id string, status model.TemplateStatus) error {
	result := r.db.Model(&model.Template{}).
		Where("id = ? AND deleted_at IS NULL", id).
		Update("status", status)
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected == 0 {
		return apperr.ErrNotFound
	}
	return nil
}

func (r *templateRepository) SoftDelete(id string) error {
	now := time.Now().UTC()
	result := r.db.Model(&model.Template{}).
		Where("id = ? AND deleted_at IS NULL", id).
		Updates(map[string]interface{}{
			"status":     model.TemplateStatusDeleted,
			"deleted_at": now,
		})
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected == 0 {
		return apperr.ErrNotFound
	}
	return nil
}

func (r *templateRepository) GetByKeyAndVersion(key, version string) (*model.Template, error) {
	var template model.Template
	err := r.db.Where("key = ? AND version = ? AND deleted_at IS NULL AND status <> ?", key, version, model.TemplateStatusDeleted).
		First(&template).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, apperr.ErrNotFound
	}
	return &template, err
}

func (r *templateRepository) CreateNodeType(nt *model.NodeType) error {
	return r.db.Transaction(func(tx *gorm.DB) error {
		if nt.ID == "" {
			nt.ID = uuid.New().String()
		}
		if err := tx.Create(nt).Error; err != nil {
			return err
		}

		defaultFields := []model.Field{
			{ID: uuid.New().String(), NodeTypeID: nt.ID, Name: "名称", Key: "name", FieldType: model.FieldTypeText, Required: true, Deletable: false, SortOrder: 0},
			{ID: uuid.New().String(), NodeTypeID: nt.ID, Name: "Key", Key: "key", FieldType: model.FieldTypeText, Required: true, Deletable: false, SortOrder: 1},
			{ID: uuid.New().String(), NodeTypeID: nt.ID, Name: "说明", Key: "description", FieldType: model.FieldTypeTextarea, Required: false, Deletable: true, SortOrder: 2},
			{ID: uuid.New().String(), NodeTypeID: nt.ID, Name: "技术说明", Key: "tech_description", FieldType: model.FieldTypeTextarea, Required: false, Deletable: true, SortOrder: 3},
		}
		if err := tx.Select("*").Create(&defaultFields).Error; err != nil {
			return err
		}
		protectedIDs := []string{defaultFields[0].ID, defaultFields[1].ID}
		if err := tx.Model(&model.Field{}).Where("id IN ?", protectedIDs).Update("deletable", false).Error; err != nil {
			return err
		}
		defaultFields[0].Deletable = false
		defaultFields[1].Deletable = false
		nt.Fields = defaultFields
		return nil
	})
}

func (r *templateRepository) GetNodeTypeByID(id string) (*model.NodeType, error) {
	var nt model.NodeType
	err := r.db.Preload("Fields", func(db *gorm.DB) *gorm.DB { return db.Order("sort_order ASC") }).First(&nt, "id = ?", id).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, apperr.ErrNotFound
	}
	return &nt, err
}

func (r *templateRepository) UpdateNodeType(nt *model.NodeType) error {
	result := r.db.Model(&model.NodeType{}).Where("id = ?", nt.ID).Updates(map[string]interface{}{
		"name":        nt.Name,
		"key":         nt.Key,
		"description": nt.Description,
	})
	return requireAffected(result)
}

func (r *templateRepository) DeleteNodeType(id string) error {
	return r.db.Transaction(func(tx *gorm.DB) error {
		var nt model.NodeType
		if err := tx.First(&nt, "id = ?", id).Error; err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return apperr.ErrNotFound
			}
			return err
		}
		return tx.Select("Fields").Delete(&nt).Error
	})
}

func (r *templateRepository) ListNodeTypes(templateID string) ([]model.NodeType, error) {
	var nodeTypes []model.NodeType
	err := r.db.Where("template_id = ?", templateID).
		Preload("Fields", func(db *gorm.DB) *gorm.DB { return db.Order("sort_order ASC") }).
		Order("sort_order ASC").Find(&nodeTypes).Error
	return nodeTypes, err
}

func (r *templateRepository) UpdateNodeTypeSortOrder(ids []string) error {
	return r.updateSortOrder("node_types", ids)
}

func (r *templateRepository) CreateField(field *model.Field) error {
	if field.ID == "" {
		field.ID = uuid.New().String()
	}
	return r.db.Select("*").Create(field).Error
}

func (r *templateRepository) GetFieldByID(id string) (*model.Field, error) {
	var field model.Field
	err := r.db.First(&field, "id = ?", id).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, apperr.ErrNotFound
	}
	return &field, err
}

func (r *templateRepository) UpdateField(field *model.Field) error {
	result := r.db.Model(&model.Field{}).Where("id = ?", field.ID).Updates(map[string]interface{}{
		"name":          field.Name,
		"key":           field.Key,
		"field_type":    field.FieldType,
		"required":      field.Required,
		"default_value": field.DefaultValue,
		"description":   field.Description,
		"options":       field.Options,
	})
	return requireAffected(result)
}

func (r *templateRepository) DeleteField(id string) error {
	return r.db.Transaction(func(tx *gorm.DB) error {
		var field model.Field
		if err := tx.First(&field, "id = ?", id).Error; err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return apperr.ErrNotFound
			}
			return err
		}
		if !field.Deletable {
			return apperr.NewBadRequest("This field cannot be deleted")
		}
		return tx.Delete(&field).Error
	})
}

func (r *templateRepository) UpdateFieldSortOrder(ids []string) error {
	return r.updateSortOrder("fields", ids)
}

func (r *templateRepository) CreateNodeRule(rule *model.NodeRule) error {
	if rule.ID == "" {
		rule.ID = uuid.New().String()
	}
	return r.db.Create(rule).Error
}

func (r *templateRepository) GetNodeRuleByID(id string) (*model.NodeRule, error) {
	var rule model.NodeRule
	err := r.db.First(&rule, "id = ?", id).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, apperr.ErrNotFound
	}
	return &rule, err
}

func (r *templateRepository) UpdateNodeRule(rule *model.NodeRule) error {
	result := r.db.Model(&model.NodeRule{}).Where("id = ?", rule.ID).Updates(map[string]interface{}{
		"parent_node_type_id": rule.ParentNodeTypeID,
		"child_node_type_id":  rule.ChildNodeTypeID,
		"min_count":           rule.MinCount,
		"max_count":           rule.MaxCount,
		"is_root_rule":        rule.IsRootRule,
	})
	return requireAffected(result)
}

func (r *templateRepository) DeleteNodeRule(id string) error {
	result := r.db.Delete(&model.NodeRule{}, "id = ?", id)
	return requireAffected(result)
}

func (r *templateRepository) ListNodeRules(templateID string) ([]model.NodeRule, error) {
	var rules []model.NodeRule
	err := r.db.Where("template_id = ?", templateID).Order("created_at ASC").Find(&rules).Error
	return rules, err
}

func (r *templateRepository) updateSortOrder(table string, ids []string) error {
	return r.db.Transaction(func(tx *gorm.DB) error {
		for index, id := range ids {
			result := tx.Table(table).Where("id = ?", id).Update("sort_order", index)
			if err := requireAffected(result); err != nil {
				return fmt.Errorf("update %s sort order: %w", table, err)
			}
		}
		return nil
	})
}

func requireAffected(result *gorm.DB) error {
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected == 0 {
		return apperr.ErrNotFound
	}
	return nil
}
