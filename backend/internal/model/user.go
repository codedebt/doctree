package model

import (
	"time"

	"gorm.io/gorm"
)

type Role string

const (
	RoleSuperAdmin    Role = "super_admin"
	RoleSystemAdmin   Role = "system_admin"
	RoleTemplateAdmin Role = "template_admin"
	RoleProjectAdmin  Role = "project_admin"
	RoleEditor        Role = "editor"
	RoleViewer        Role = "viewer"
)

var roleHierarchy = map[Role]int{
	RoleSuperAdmin:    6,
	RoleSystemAdmin:   5,
	RoleTemplateAdmin: 4,
	RoleProjectAdmin:  3,
	RoleEditor:        2,
	RoleViewer:        1,
}

func (r Role) AtLeast(other Role) bool {
	return roleHierarchy[r] >= roleHierarchy[other]
}

func (r Role) IsValid() bool {
	_, ok := roleHierarchy[r]
	return ok
}

type User struct {
	ID         string         `gorm:"primaryKey" json:"id"`
	Username   string         `gorm:"uniqueIndex;not null" json:"username"`
	Email      string         `json:"email"`
	ExternalID string         `json:"external_id"`
	Provider   string         `json:"provider"`
	Role       Role           `gorm:"not null;default:'viewer'" json:"role"`
	CreatedAt  time.Time      `json:"created_at"`
	UpdatedAt  time.Time      `json:"updated_at"`
	DeletedAt  gorm.DeletedAt `gorm:"index" json:"-"`
}
