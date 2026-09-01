package model

import (
	"time"

	"gorm.io/gorm"
)

type ProjectStatus string

const (
	ProjectStatusDraft     ProjectStatus = "draft"
	ProjectStatusPublished ProjectStatus = "published"
	ProjectStatusDeleted   ProjectStatus = "deleted"
)

type Project struct {
	ID              string         `gorm:"primaryKey" json:"id"`
	Name            string         `gorm:"not null" json:"name"`
	Key             string         `gorm:"not null" json:"key"`
	Description     string         `json:"description"`
	Version         string         `gorm:"not null" json:"version"`
	VersionNote     string         `json:"version_note"`
	Status          ProjectStatus  `gorm:"not null;default:'draft'" json:"status"`
	TemplateID      string         `gorm:"not null" json:"template_id"`
	ParentVersionID *string        `json:"parent_version_id"`
	CreatedByID     string         `json:"created_by_id"`
	CreatedAt       time.Time      `json:"created_at"`
	UpdatedAt       time.Time      `json:"updated_at"`
	DeletedAt       gorm.DeletedAt `gorm:"index" json:"-"`
}
