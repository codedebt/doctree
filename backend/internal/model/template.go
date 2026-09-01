package model

import (
	"time"

	"gorm.io/gorm"
)

type TemplateStatus string

const (
	TemplateStatusDraft     TemplateStatus = "draft"
	TemplateStatusPublished TemplateStatus = "published"
	TemplateStatusDeleted   TemplateStatus = "deleted"
)

type Template struct {
	ID              string         `gorm:"primaryKey" json:"id"`
	Name            string         `gorm:"not null" json:"name"`
	Key             string         `gorm:"not null" json:"key"`
	Version         string         `gorm:"not null" json:"version"`
	VersionNote     string         `json:"version_note"`
	Status          TemplateStatus `gorm:"not null;default:'draft'" json:"status"`
	ParentVersionID *string        `json:"parent_version_id"`
	CreatedByID     string         `json:"created_by_id"`
	CreatedAt       time.Time      `json:"created_at"`
	UpdatedAt       time.Time      `json:"updated_at"`
	DeletedAt       gorm.DeletedAt `gorm:"index" json:"-"`
	NodeTypes       []NodeType     `gorm:"foreignKey:TemplateID" json:"node_types,omitempty"`
	NodeRules       []NodeRule     `gorm:"foreignKey:TemplateID" json:"node_rules,omitempty"`
}

type FieldType string

const (
	FieldTypeText        FieldType = "text"
	FieldTypeTextarea    FieldType = "textarea"
	FieldTypeSelect      FieldType = "select"
	FieldTypeMultiSelect FieldType = "multiselect"
	FieldTypeCheckbox    FieldType = "checkbox"
	FieldTypeDate        FieldType = "date"
)

type NodeType struct {
	ID          string    `gorm:"primaryKey" json:"id"`
	TemplateID  string    `gorm:"not null;index" json:"template_id"`
	Name        string    `gorm:"not null" json:"name"`
	Key         string    `gorm:"not null" json:"key"`
	Description string    `json:"description"`
	SortOrder   int       `gorm:"not null;default:0" json:"sort_order"`
	Fields      []Field   `gorm:"foreignKey:NodeTypeID;constraint:OnDelete:CASCADE" json:"fields,omitempty"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

type Field struct {
	ID           string    `gorm:"primaryKey" json:"id"`
	NodeTypeID   string    `gorm:"not null;index" json:"node_type_id"`
	Name         string    `gorm:"not null" json:"name"`
	Key          string    `gorm:"not null" json:"key"`
	FieldType    FieldType `gorm:"column:field_type;not null" json:"field_type"`
	Required     bool      `gorm:"not null;default:false" json:"required"`
	DefaultValue string    `json:"default_value"`
	Description  string    `json:"description"`
	Options      string    `json:"options"`
	SortOrder    int       `gorm:"not null;default:0" json:"sort_order"`
	Deletable    bool      `gorm:"not null;default:true" json:"deletable"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

type NodeRule struct {
	ID               string    `gorm:"primaryKey" json:"id"`
	TemplateID       string    `gorm:"not null;index" json:"template_id"`
	ParentNodeTypeID string    `gorm:"not null" json:"parent_node_type_id"`
	ChildNodeTypeID  string    `gorm:"not null" json:"child_node_type_id"`
	MinCount         int       `gorm:"not null;default:0" json:"min_count"`
	MaxCount         int       `gorm:"not null;default:0" json:"max_count"`
	IsRootRule       bool      `gorm:"not null;default:false" json:"is_root_rule"`
	CreatedAt        time.Time `json:"created_at"`
	UpdatedAt        time.Time `json:"updated_at"`
}
