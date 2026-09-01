package model

import (
	"time"

	"gorm.io/gorm"
)

type Node struct {
	ID          string           `gorm:"primaryKey" json:"id"`
	ProjectID   string           `gorm:"not null;index" json:"project_id"`
	ParentID    *string          `gorm:"index" json:"parent_id"`
	NodeTypeKey string           `gorm:"not null" json:"node_type_key"`
	Name        string           `gorm:"not null" json:"name"`
	SortOrder   int              `gorm:"not null;default:0" json:"sort_order"`
	CreatedAt   time.Time        `json:"created_at"`
	UpdatedAt   time.Time        `json:"updated_at"`
	DeletedAt   gorm.DeletedAt   `gorm:"index" json:"-"`
	FieldValues []NodeFieldValue `gorm:"foreignKey:NodeID" json:"field_values,omitempty"`
	Children    []Node           `gorm:"foreignKey:ParentID" json:"children,omitempty"`
}

type NodeFieldValue struct {
	ID        string    `gorm:"primaryKey" json:"id"`
	NodeID    string    `gorm:"not null;uniqueIndex:idx_node_field" json:"node_id"`
	FieldKey  string    `gorm:"not null;uniqueIndex:idx_node_field" json:"field_key"`
	Value     string    `json:"value"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

type NodePermission struct {
	ID             string    `gorm:"primaryKey" json:"id"`
	NodeID         string    `gorm:"not null;uniqueIndex:idx_node_user" json:"node_id"`
	UserID         string    `gorm:"not null;uniqueIndex:idx_node_user" json:"user_id"`
	PermissionType string    `gorm:"not null" json:"permission_type"`
	CreatedAt      time.Time `json:"created_at"`
	UpdatedAt      time.Time `json:"updated_at"`
}
