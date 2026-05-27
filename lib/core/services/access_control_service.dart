import 'package:lubrication_indicator/features/auth/data/models/user_model.dart';

class AccessControlService {
  static const String roleSuperAdmin = 'super admin';
  static const String roleAdmin = 'admin';
  static const String roleUser = 'user';

  static const String pCreateClient = 'create_client';
  static const String pCreateUsers = 'create_users';
  static const String pGrantUsers = 'grant_users';
  static const String pCreateTanks = 'create_tanks';
  static const String pDeleteTanks = 'delete_tanks';
  static const String pModifyTanks = 'modify_tanks';
  static const String pAllocateUsersToClients = 'allocate_users_to_clients';
  static const String pOpenAdminPage = 'open_admin_page';
  static const String pViewSettings = 'view_settings';
  static const String pChangeSettings = 'change_settings';

  static const List<String> allPrivileges = [
    pCreateClient,
    pCreateUsers,
    pGrantUsers,
    pCreateTanks,
    pDeleteTanks,
    pModifyTanks,
    pAllocateUsersToClients,
    pOpenAdminPage,
    pViewSettings,
    pChangeSettings,
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
        pCreateUsers: true,
        pGrantUsers: true,
        pCreateTanks: true,
        pDeleteTanks: true,
        pModifyTanks: true,
        pAllocateUsersToClients: true,
        pViewSettings: true,
        pChangeSettings: true,
      };
    }
    return const {};
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
