package repository

import (
	"errors"
	"fmt"
	"time"

	"doctree-backend/internal/apperr"
	"doctree-backend/internal/model"
	"github.com/google/uuid"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

type nodeRepository struct {
	db *gorm.DB
}

func NewNodeRepository(db *gorm.DB) NodeRepository {
	return &nodeRepository{db: db}
}

func (r *nodeRepository) Create(node *model.Node) error {
	if node.ID == "" {
		node.ID = uuid.New().String()
	}
	if node.CreatedAt.IsZero() {
		node.CreatedAt = time.Now().UTC()
	}
	return r.db.Omit("FieldValues", "Children").Create(node).Error
}

func (r *nodeRepository) GetByID(id string) (*model.Node, error) {
	var node model.Node
	err := r.db.Where("id = ? AND deleted_at IS NULL", id).
		Preload("FieldValues", func(db *gorm.DB) *gorm.DB { return db.Order("created_at ASC") }).
		First(&node).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, apperr.ErrNotFound
	}
	return &node, err
}

func (r *nodeRepository) GetTree(projectID string) ([]model.Node, error) {
	var nodes []model.Node
	err := r.db.Where("project_id = ? AND deleted_at IS NULL", projectID).
		Preload("FieldValues", func(db *gorm.DB) *gorm.DB { return db.Order("created_at ASC") }).
		Order("sort_order ASC, created_at ASC").Find(&nodes).Error
	return nodes, err
}

func (r *nodeRepository) Update(node *model.Node) error {
	result := r.db.Model(&model.Node{}).
		Where("id = ? AND deleted_at IS NULL", node.ID).
		Updates(map[string]interface{}{
			"name":          node.Name,
			"node_type_key": node.NodeTypeKey,
			"sort_order":    node.SortOrder,
		})
	return requireAffected(result)
}

func (r *nodeRepository) SoftDelete(id string) error {
	result := r.db.Where("id = ? AND deleted_at IS NULL", id).Delete(&model.Node{})
	return requireAffected(result)
}

func (r *nodeRepository) SoftDeleteChildren(parentID string) error {
	return r.db.Transaction(func(tx *gorm.DB) error {
		return softDeleteDescendants(tx, parentID)
	})
}

func softDeleteDescendants(tx *gorm.DB, parentID string) error {
	var children []model.Node
	if err := tx.Select("id").Where("parent_id = ? AND deleted_at IS NULL", parentID).Find(&children).Error; err != nil {
		return err
	}
	for _, child := range children {
		if err := softDeleteDescendants(tx, child.ID); err != nil {
			return err
		}
		if err := tx.Where("id = ? AND deleted_at IS NULL", child.ID).Delete(&model.Node{}).Error; err != nil {
			return err
		}
	}
	return nil
}

func (r *nodeRepository) UpdateSortOrder(ids []string) error {
	return r.db.Transaction(func(tx *gorm.DB) error {
		for index, id := range ids {
			result := tx.Model(&model.Node{}).Where("id = ? AND deleted_at IS NULL", id).Update("sort_order", index)
			if err := requireAffected(result); err != nil {
				return fmt.Errorf("update node sort order: %w", err)
			}
		}
		return nil
	})
}

func (r *nodeRepository) UpsertFieldValue(fv *model.NodeFieldValue) error {
	if fv.ID == "" {
		fv.ID = uuid.New().String()
	}
	return r.db.Clauses(clause.OnConflict{
		Columns:   []clause.Column{{Name: "node_id"}, {Name: "field_key"}},
		DoUpdates: clause.AssignmentColumns([]string{"value", "updated_at"}),
	}).Create(fv).Error
}

func (r *nodeRepository) GetFieldValues(nodeID string) ([]model.NodeFieldValue, error) {
	var values []model.NodeFieldValue
	err := r.db.Where("node_id = ?", nodeID).Order("created_at ASC").Find(&values).Error
	return values, err
}

func (r *nodeRepository) DeleteFieldValuesByFieldKey(nodeID, fieldKey string) error {
	return r.db.Where("node_id = ? AND field_key = ?", nodeID, fieldKey).
		Delete(&model.NodeFieldValue{}).Error
}

func (r *nodeRepository) CreatePermission(perm *model.NodePermission) error {
	if perm.ID == "" {
		perm.ID = uuid.New().String()
	}
	return r.db.Create(perm).Error
}

func (r *nodeRepository) DeletePermission(id string) error {
	return requireAffected(r.db.Delete(&model.NodePermission{}, "id = ?", id))
}

func (r *nodeRepository) ListPermissions(nodeID string) ([]model.NodePermission, error) {
	var permissions []model.NodePermission
	err := r.db.Where("node_id = ?", nodeID).Order("created_at ASC").Find(&permissions).Error
	return permissions, err
}

func (r *nodeRepository) GetEffectivePermission(nodeID, userID string) (*model.NodePermission, error) {
	currentID := nodeID
	visited := make(map[string]struct{})
	for currentID != "" {
		if _, duplicate := visited[currentID]; duplicate {
			return nil, fmt.Errorf("node parent cycle detected")
		}
		visited[currentID] = struct{}{}

		node, err := r.GetByID(currentID)
		if err != nil {
			return nil, err
		}
		var permission model.NodePermission
		err = r.db.Where("node_id = ? AND user_id = ?", node.ID, userID).First(&permission).Error
		if err == nil {
			return &permission, nil
		}
		if !errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, err
		}
		if node.ParentID == nil {
			break
		}
		currentID = *node.ParentID
	}
	return nil, apperr.ErrNotFound
}

func (r *nodeRepository) GetChildrenCount(projectID, parentID, nodeTypeKey string) (int64, error) {
	var count int64
	err := r.db.Model(&model.Node{}).
		Where("project_id = ? AND parent_id = ? AND node_type_key = ? AND deleted_at IS NULL", projectID, parentID, nodeTypeKey).
		Count(&count).Error
	return count, err
}

func (r *nodeRepository) GetNodesByType(projectID, nodeTypeKey string) ([]model.Node, error) {
	var nodes []model.Node
	err := r.db.Where("project_id = ? AND node_type_key = ? AND deleted_at IS NULL", projectID, nodeTypeKey).
		Preload("FieldValues", func(db *gorm.DB) *gorm.DB { return db.Order("created_at ASC") }).
		Order("created_at ASC").Find(&nodes).Error
	return nodes, err
}
