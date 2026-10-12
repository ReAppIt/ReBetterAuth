import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:re_better_auth/re_better_auth.dart';

final authClient = createAuthClient(
  baseURL: 'http://localhost:8081',
  plugins: [
    flutterClient(
      scheme: 'myapp',
      storagePrefix: 'myapp',
      storage: const SecureStore(),
    ),
  ],
);

void main() => runApp(const MaterialApp(home: HomePage()));

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('re_better_auth')),
    body: Center(
      child: ValueListenableBuilder<AuthQueryState<SessionData>>(
        valueListenable: authClient.useSession,
        builder: (context, session, _) {
          if (session.isPending) return const CircularProgressIndicator();
          final user = session.data?.user;
          if (user == null) return const SignInButtons();
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Welcome, ${user.name}'),
              TextButton(
                onPressed: authClient.signOut,
                child: const Text('Sign out'),
              ),
              const TextButton(
                onPressed: callOwnApi,
                child: Text('Call my API'),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class SignInButtons extends StatelessWidget {
  const SignInButtons({super.key});

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      FilledButton(
        onPressed: () async {
          final (data: _, :error) = await authClient.signIn.email(
            email: 'test@example.com',
            password: 'password1234',
          );
          if (error != null && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(error.message ?? 'Sign-in failed')),
            );
          }
        },
        child: const Text('Sign in with email'),
      ),
      OutlinedButton(
        onPressed: () => authClient.signIn.social(
          provider: 'google',
          callbackURL: '/dashboard',
        ),
        child: const Text('Sign in with Google'),
      ),
    ],
  );
}

Future<void> callOwnApi() async {
  final cookie = await authClient.getCookie();
  await Dio().get<Object?>(
    'http://localhost:8081/api/secure-endpoint',
    options: Options(headers: {'Cookie': cookie}),
  );
  final (:data, error: _) = await authClient<Map<String, Object?>>(
    '/convex/token',
  );
  debugPrint('Convex token: ${data?['token']}');
}
