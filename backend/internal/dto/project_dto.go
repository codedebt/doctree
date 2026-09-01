package dto

// CreateProjectRequest contains the fields required to create a project.
type CreateProjectRequest struct {
	Name        string `json:"name"`
	Key         string `json:"key"`
	Description string `json:"description"`
	Version     string `json:"version"`
	VersionNote string `json:"version_note"`
	TemplateID  string `json:"template_id"`
}

// UpdateProjectRequest contains mutable project fields.
type UpdateProjectRequest struct {
	Name        *string `json:"name,omitempty"`
	Description *string `json:"description,omitempty"`
	VersionNote *string `json:"version_note,omitempty"`
}

// ProjectNewVersionRequest describes a new project version.
type ProjectNewVersionRequest struct {
	Version       string  `json:"version"`
	VersionNote   string  `json:"version_note"`
	NewTemplateID *string `json:"new_template_id,omitempty"`
}
