import 'package:lubrication_indicator/features/auth/data/models/user_model.dart';
import 'package:lubrication_indicator/features/auth/data/repositories/auth_repository.dart';

class AuthController {
  AuthController({AuthRepository? repository})
    : _repository = repository ?? AuthRepository();

  final AuthRepository _repository;

  Future<UserModel> loginUser({
    required String username,
    required String password,
  }) async {
    return _repository.login(username.trim(), password);
  }

  Future<UserModel> loginAdmin({
    required String username,
    required String password,
  }) async {
    final user = await loginUser(username: username, password: password);
    if (user.role != 'admin') {
      throw Exception('Not an admin account');
    }
    return user;
  }

  String toDisplayError(Object error) {
    return error.toString().replaceAll('Exception: ', '').trim();
  }
}

