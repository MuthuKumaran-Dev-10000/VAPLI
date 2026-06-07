import 'package:lubrication_indicator/features/auth/data/models/user_model.dart';

class AccessControlService {
  static const String roleSuperAdmin = 'super admin';
  static const String roleAdmin = 'admin';
  static const String roleUser = 'user';

  static const String pOpenAdminPage = 'open_admin_page';
  static const String pViewAdminTanks = 'view_admin_tanks';
  static const String pViewAdminClients = 'view_admin_clients';
  static const String pViewAdminUsers = 'view_admin_users';
  static const String pViewSettings = 'view_settings';
  static const String pViewAuditLogs = 'view_audit_logs';

  static const String pCreateClient = 'create_client';
  static const String pCreateUsers = 'create_users';
  static const String pGrantUsers = 'grant_users';
  static const String pCreateTanks = 'create_tanks';
  static const String pDeleteTanks = 'delete_tanks';
  static const String pModifyTanks = 'modify_tanks';
  static const String pAllocateUsersToClients = 'allocate_users_to_clients';
  static const String pChangeSettings = 'change_settings';

  static const String pHistoricalUpload = 'historical_upload'; // 🔖 Added for Historical Upload Permission

  static const List<String> viewPrivileges = [
    pOpenAdminPage,
    pViewAdminTanks,
    pViewAdminClients,
    pViewAdminUsers,
    pViewSettings,
    pViewAuditLogs,
  ];

  static const List<String> actionPrivileges = [
    pCreateClient,
    pCreateUsers,
    pGrantUsers,
    pCreateTanks,
    pDeleteTanks,
    pModifyTanks,
    pAllocateUsersToClients,
    pChangeSettings,
    pHistoricalUpload, // 🔖 Added for Historical Upload Permission
  ];

  static const List<String> allPrivileges = [
    pOpenAdminPage,
    pViewAdminTanks,
    pViewAdminClients,
    pViewAdminUsers,
    pViewSettings,
    pViewAuditLogs,
    pCreateClient,
    pCreateUsers,
    pGrantUsers,
    pCreateTanks,
    pDeleteTanks,
    pModifyTanks,
    pAllocateUsersToClients,
    pChangeSettings,
    pHistoricalUpload, // 🔖 Added for Historical Upload Permission
  ];

  static int rankOf(String role) {
    switch (role.trim().toLowerCase()) {
      case roleSuperAdmin:
        return 3;
      case roleAdmin:
        return 2;
      default:
        return 1;
    }
  }

  static Map<String, bool> defaultPrivilegesForRole(String role) {
    final r = role.trim().toLowerCase();
    if (r == roleSuperAdmin) {
      return {for (final p in allPrivileges) p: true};
    }
    if (r == roleAdmin) {
      return {
        pOpenAdminPage: true,
        pViewAdminTanks: true,
        pViewAdminUsers: true,
        pViewSettings: true,
        pCreateUsers: true,
        pGrantUsers: true,
        pCreateTanks: true,
        pDeleteTanks: true,
        pModifyTanks: true,
        pAllocateUsersToClients: true,
        pChangeSettings: true,
        pViewAdminClients: false,
        pViewAuditLogs: false,
      };
    }
    if (r == roleUser) {
      return {
        pOpenAdminPage: false,
        pViewAdminTanks: false,
        pViewAdminClients: false,
        pViewAdminUsers: false,
        pViewSettings: false,
        pViewAuditLogs: false,
        pCreateClient: false,
        pCreateUsers: false,
        pGrantUsers: false,
        pCreateTanks: false,
        pDeleteTanks: false,
        pModifyTanks: false,
        pAllocateUsersToClients: false,
        pChangeSettings: false,
      };
    }
    return const {};
  }

  static bool isViewPrivilege(String privilege) {
    return viewPrivileges.contains(privilege);
  }

  static Map<String, bool> sanitizePrivilegesForRole(
    String role,
    Map<String, bool> privileges,
  ) {
    final normalized = <String, bool>{
      ...defaultPrivilegesForRole(role),
      ...privileges,
    };
    if (role.trim().toLowerCase() == roleUser) {
      for (final privilege in actionPrivileges) {
        normalized[privilege] = false;
      }
    }
    return normalized;
  }

  static bool can(UserModel? user, String privilege) {
    if (user == null) return false;
    if (user.role.trim().toLowerCase() == roleSuperAdmin) return true;
    final explicit = user.privileges[privilege];
    if (explicit != null) return explicit;
    return defaultPrivilegesForRole(user.role)[privilege] == true;
  }

  static bool canManage(UserModel actor, UserModel target) {
    return rankOf(actor.role) > rankOf(target.role);
  }

  static bool isAdminLike(UserModel? user) {
    if (user == null) return false;
    final role = user.role.trim().toLowerCase();
    return role == roleSuperAdmin || role == roleAdmin;
  }
}
