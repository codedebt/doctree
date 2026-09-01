package service

import (
	"strings"

	"doctree-backend/internal/apperr"
	"doctree-backend/internal/model"
	"doctree-backend/internal/repository"
)

const (
	defaultPageSize = 20
	maxPageSize     = 100
)

type UserService struct {
	userRepo repository.UserRepository
}

func NewUserService(userRepo repository.UserRepository) *UserService {
	return &UserService{userRepo: userRepo}
}

func (s *UserService) ListUsers(page, pageSize int) ([]model.User, int64, error) {
	if page < 1 {
		page = 1
	}
	if pageSize < 1 {
		pageSize = defaultPageSize
	}
	if pageSize > maxPageSize {
		pageSize = maxPageSize
	}
	return s.userRepo.List((page-1)*pageSize, pageSize)
}

func (s *UserService) UpdateUserRole(operatorID string, operatorRole model.Role, targetUserID string, newRole model.Role) error {
	if strings.TrimSpace(operatorID) == "" || !operatorRole.IsValid() {
		return apperr.ErrUnauthorized
	}
	if strings.TrimSpace(targetUserID) == "" || !newRole.IsValid() {
		return apperr.NewBadRequest("A valid user ID and role are required")
	}
	if operatorID == targetUserID {
		return apperr.NewBadRequest("You cannot change your own role")
	}
	if !operatorRole.AtLeast(model.RoleProjectAdmin) {
		return apperr.NewForbidden("Your role cannot manage users")
	}
	if newRole.AtLeast(operatorRole) {
		return apperr.NewForbidden("You cannot assign a role equal to or higher than your own")
	}

	targetUser, err := s.userRepo.GetByID(targetUserID)
	if err != nil {
		return err
	}
	if targetUser.Role.AtLeast(operatorRole) {
		return apperr.NewForbidden("You cannot modify a user with an equal or higher role")
	}

	return s.userRepo.UpdateRole(targetUserID, newRole)
}
