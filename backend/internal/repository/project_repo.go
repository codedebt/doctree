package repository

import (
	"errors"
	"time"

	"doctree-backend/internal/apperr"
	"doctree-backend/internal/model"
	"github.com/google/uuid"
	"gorm.io/gorm"
)

type projectRepository struct {
	db *gorm.DB
}

func NewProjectRepository(db *gorm.DB) ProjectRepository {
	return &projectRepository{db: db}
}

func (r *projectRepository) Create(project *model.Project) error {
	if project.ID == "" {
		project.ID = uuid.New().String()
	}
	if project.CreatedAt.IsZero() {
		project.CreatedAt = time.Now().UTC()
	}
	return r.db.Create(project).Error
}

func (r *projectRepository) GetByID(id string) (*model.Project, error) {
	var project model.Project
	err := r.db.Where("id = ? AND deleted_at IS NULL AND status <> ?", id, model.ProjectStatusDeleted).
		First(&project).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, apperr.ErrNotFound
	}
	return &project, err
}

func (r *projectRepository) List(_ string, offset, limit int) ([]model.Project, int64, error) {
	query := r.db.Model(&model.Project{}).
		Where("deleted_at IS NULL AND status <> ?", model.ProjectStatusDeleted)
	var total int64
	if err := query.Count(&total).Error; err != nil {
		return nil, 0, err
	}
	var projects []model.Project
	if err := query.Order("created_at DESC").Offset(offset).Limit(limit).Find(&projects).Error; err != nil {
		return nil, 0, err
	}
	return projects, total, nil
}

func (r *projectRepository) Update(project *model.Project) error {
	result := r.db.Model(&model.Project{}).
		Where("id = ? AND deleted_at IS NULL", project.ID).
		Updates(map[string]interface{}{
			"name":              project.Name,
			"description":       project.Description,
			"version_note":      project.VersionNote,
			"status":            project.Status,
			"template_id":       project.TemplateID,
			"parent_version_id": project.ParentVersionID,
		})
	return requireAffected(result)
}

func (r *projectRepository) SoftDelete(id string) error {
	now := time.Now().UTC()
	result := r.db.Model(&model.Project{}).
		Where("id = ? AND deleted_at IS NULL", id).
		Updates(map[string]interface{}{
			"status":     model.ProjectStatusDeleted,
			"deleted_at": now,
		})
	return requireAffected(result)
}

func (r *projectRepository) RunInTransaction(fn func(ProjectRepository, NodeRepository) error) error {
	if fn == nil {
		return apperr.NewBadRequest("Transaction callback is required")
	}
	return r.db.Transaction(func(tx *gorm.DB) error {
		return fn(&projectRepository{db: tx}, &nodeRepository{db: tx})
	})
}
