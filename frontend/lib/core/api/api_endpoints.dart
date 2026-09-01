class ApiEndpoints {
  static const String baseUrl = 'http://localhost:8080';

  // Auth
  static const String authProviders = '/api/auth/providers';
  static const String devLogin = '/api/auth/dev-login';
  static String oidcLogin(String provider) => '/api/auth/oidc/$provider/login';
  static String oidcCallback(String provider) =>
      '/api/auth/oidc/$provider/callback';
  static const String authMe = '/api/auth/me';

  // Users
  static const String users = '/api/users';
  static String userRole(String id) => '/api/users/$id/role';

  // Templates
  static const String templates = '/api/templates';
  static String template(String id) => '/api/templates/$id';
  static String templatePublish(String id) => '/api/templates/$id/publish';
  static String templateNewVersion(String id) =>
      '/api/templates/$id/new-version';
  static String templateNodeTypes(String id) => '/api/templates/$id/node-types';
  static String templateNodeType(String tplId, String ntId) =>
      '/api/templates/$tplId/node-types/$ntId';
  static String templateNodeTypeSort(String id) =>
      '/api/templates/$id/node-types/sort';
  static String templateFields(String tplId, String ntId) =>
      '/api/templates/$tplId/node-types/$ntId/fields';
  static String templateField(String tplId, String ntId, String fId) =>
      '/api/templates/$tplId/node-types/$ntId/fields/$fId';
  static String templateFieldSort(String tplId, String ntId) =>
      '/api/templates/$tplId/node-types/$ntId/fields/sort';
  static String templateRules(String id) => '/api/templates/$id/rules';
  static String templateRule(String tplId, String rId) =>
      '/api/templates/$tplId/rules/$rId';
  static String templateExport(String id) => '/api/templates/$id/export';
  static const String templateImport = '/api/templates/import';

  // Projects
  static const String projects = '/api/projects';
  static String project(String id) => '/api/projects/$id';
  static String projectPublish(String id) => '/api/projects/$id/publish';
  static String projectNewVersion(String id) => '/api/projects/$id/new-version';
  static String projectNodes(String id) => '/api/projects/$id/nodes';
  static String projectNode(String pId, String nId) =>
      '/api/projects/$pId/nodes/$nId';
  static String projectNodeSort(String id) => '/api/projects/$id/nodes/sort';
  static String projectNodePermissions(String pId, String nId) =>
      '/api/projects/$pId/nodes/$nId/permissions';
  static String projectNodePermission(
    String pId,
    String nId,
    String permId,
  ) =>
      '/api/projects/$pId/nodes/$nId/permissions/$permId';
  static String projectExport(String id, String format) =>
      '/api/projects/$id/export?format=$format';
  static const String projectImport = '/api/projects/import';
}
