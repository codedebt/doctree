package dto

type CreateTemplateRequest struct {
	Name        string `json:"name"`
	Key         string `json:"key"`
	Version     string `json:"version"`
	VersionNote string `json:"version_note"`
}

type UpdateTemplateRequest struct {
	Name        *string `json:"name,omitempty"`
	VersionNote *string `json:"version_note,omitempty"`
}

type CreateNodeTypeRequest struct {
	Name        string `json:"name"`
	Key         string `json:"key"`
	Description string `json:"description"`
}

type UpdateNodeTypeRequest struct {
	Name        *string `json:"name,omitempty"`
	Key         *string `json:"key,omitempty"`
	Description *string `json:"description,omitempty"`
}

type SortRequest struct {
	IDs []string `json:"ids"`
}

type CreateFieldRequest struct {
	Name         string `json:"name"`
	Key          string `json:"key"`
	FieldType    string `json:"field_type"`
	Required     bool   `json:"required"`
	DefaultValue string `json:"default_value"`
	Description  string `json:"description"`
	Options      string `json:"options"`
}

type UpdateFieldRequest struct {
	Name         *string `json:"name,omitempty"`
	Key          *string `json:"key,omitempty"`
	FieldType    *string `json:"field_type,omitempty"`
	Required     *bool   `json:"required,omitempty"`
	DefaultValue *string `json:"default_value,omitempty"`
	Description  *string `json:"description,omitempty"`
	Options      *string `json:"options,omitempty"`
}

type CreateNodeRuleRequest struct {
	ParentNodeTypeID string `json:"parent_node_type_id"`
	ChildNodeTypeID  string `json:"child_node_type_id"`
	MinCount         int    `json:"min_count"`
	MaxCount         int    `json:"max_count"`
	IsRootRule       bool   `json:"is_root_rule"`
}

type UpdateNodeRuleRequest struct {
	ChildNodeTypeID *string `json:"child_node_type_id,omitempty"`
	MinCount        *int    `json:"min_count,omitempty"`
	MaxCount        *int    `json:"max_count,omitempty"`
}

type NewVersionRequest struct {
	Version     string `json:"version"`
	VersionNote string `json:"version_note"`
}
