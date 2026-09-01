package repository

import (
	"errors"
	"fmt"

	"doctree-backend/internal/apperr"
	"doctree-backend/internal/model"
	"github.com/google/uuid"
	"gorm.io/gorm"
)

type userRepository struct {
	db *gorm.DB
}

func NewUserRepository(db *gorm.DB) UserRepository {
	return &userRepository{db: db}
}

func (r *userRepository) Create(user *model.User) error {
	if user.ID == "" {
		user.ID = uuid.NewString()
	}
	if err := r.db.Create(user).Error; err != nil {
		return fmt.Errorf("create user: %w", err)
	}
	return nil
}

func (r *userRepository) GetByID(id string) (*model.User, error) {
	var user model.User
	if err := r.db.First(&user, "id = ?", id).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, apperr.ErrNotFound
		}
		return nil, fmt.Errorf("get user by ID: %w", err)
	}
	return &user, nil
}

func (r *userRepository) GetByUsername(username string) (*model.User, error) {
	var user model.User
	if err := r.db.First(&user, "username = ?", username).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, apperr.ErrNotFound
		}
		return nil, fmt.Errorf("get user by username: %w", err)
	}
	return &user, nil
}

func (r *userRepository) GetByExternalID(provider, externalID string) (*model.User, error) {
	var user model.User
	if err := r.db.First(&user, "provider = ? AND external_id = ?", provider, externalID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, apperr.ErrNotFound
		}
		return nil, fmt.Errorf("get user by external ID: %w", err)
	}
	return &user, nil
}

func (r *userRepository) List(offset, limit int) ([]model.User, int64, error) {
	var (
		users []model.User
		total int64
	)
	if err := r.db.Model(&model.User{}).Count(&total).Error; err != nil {
		return nil, 0, fmt.Errorf("count users: %w", err)
	}
	if err := r.db.Order("created_at ASC").Offset(offset).Limit(limit).Find(&users).Error; err != nil {
		return nil, 0, fmt.Errorf("list users: %w", err)
	}
	return users, total, nil
}

func (r *userRepository) UpdateRole(id string, role model.Role) error {
	result := r.db.Model(&model.User{}).Where("id = ?", id).Update("role", role)
	if result.Error != nil {
		return fmt.Errorf("update user role: %w", result.Error)
	}
	if result.RowsAffected == 0 {
		return apperr.ErrNotFound
	}
	return nil
}

func (r *userRepository) Count() (int64, error) {
	var count int64
	if err := r.db.Model(&model.User{}).Count(&count).Error; err != nil {
		return 0, fmt.Errorf("count users: %w", err)
	}
	return count, nil
}
