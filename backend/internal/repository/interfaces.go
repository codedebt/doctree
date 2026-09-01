package repository

import "doctree-backend/internal/model"

type UserRepository interface {
	Create(user *model.User) error
	GetByID(id string) (*model.User, error)
	GetByUsername(username string) (*model.User, error)
	GetByExternalID(provider, externalID string) (*model.User, error)
	List(offset, limit int) ([]model.User, int64, error)
	UpdateRole(id string, role model.Role) error
	Count() (int64, error)
}

type TemplateRepository interface {
	Create(template *model.Template) error
	GetByID(id string) (*model.Template, error)
	List(status string, offset, limit int) ([]model.Template, int64, error)
	Update(template *model.Template) error
	SoftDelete(id string) error
	GetByKeyAndVersion(key, version string) (*model.Template, error)

	CreateNodeType(nt *model.NodeType) error
	GetNodeTypeByID(id string) (*model.NodeType, error)
	UpdateNodeType(nt *model.NodeType) error
	DeleteNodeType(id string) error
	ListNodeTypes(templateID string) ([]model.NodeType, error)
	UpdateNodeTypeSortOrder(ids []string) error

	CreateField(field *model.Field) error
	GetFieldByID(id string) (*model.Field, error)
	UpdateField(field *model.Field) error
	DeleteField(id string) error
	UpdateFieldSortOrder(ids []string) error

	CreateNodeRule(rule *model.NodeRule) error
	GetNodeRuleByID(id string) (*model.NodeRule, error)
	UpdateNodeRule(rule *model.NodeRule) error
	DeleteNodeRule(id string) error
	ListNodeRules(templateID string) ([]model.NodeRule, error)
}

type ProjectRepository interface {
	Create(project *model.Project) error
	GetByID(id string) (*model.Project, error)
	List(userID string, offset, limit int) ([]model.Project, int64, error)
	Update(project *model.Project) error
	SoftDelete(id string) error
}

type NodeRepository interface {
	Create(node *model.Node) error
	GetByID(id string) (*model.Node, error)
	GetTree(projectID string) ([]model.Node, error)
	Update(node *model.Node) error
	SoftDelete(id string) error
	SoftDeleteChildren(parentID string) error
	UpdateSortOrder(ids []string) error

	UpsertFieldValue(fv *model.NodeFieldValue) error
	GetFieldValues(nodeID string) ([]model.NodeFieldValue, error)
	DeleteFieldValuesByFieldKey(nodeID, fieldKey string) error

	CreatePermission(perm *model.NodePermission) error
	DeletePermission(id string) error
	ListPermissions(nodeID string) ([]model.NodePermission, error)
	GetEffectivePermission(nodeID, userID string) (*model.NodePermission, error)
	GetChildrenCount(projectID, parentID, nodeTypeKey string) (int64, error)
	GetNodesByType(projectID, nodeTypeKey string) ([]model.Node, error)
}
