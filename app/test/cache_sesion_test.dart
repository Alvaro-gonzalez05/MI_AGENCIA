import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_agencia/core/sesion.dart';
import 'package:mi_agencia/datos/repositorio.dart';

final _usuarioQaProvider = NotifierProvider<_UsuarioQa, Usuario?>(
  _UsuarioQa.new,
);

class _UsuarioQa extends Notifier<Usuario?> {
  @override
  Usuario? build() => null;

  void cambiar(Usuario? usuario) => state = usuario;
}

void main() {
  test('cambiar de usuario descarta el repositorio y sus datos en memoria', () {
    final container = ProviderContainer(
      overrides: [
        usuarioProvider.overrideWith((ref) => ref.watch(_usuarioQaProvider)),
      ],
    );
    addTearDown(container.dispose);

    final primero = container.read(repositorioProvider);
    container
        .read(_usuarioQaProvider.notifier)
        .cambiar(
          const Usuario(
            id: 'usuario-b',
            email: 'b@example.test',
            nombre: 'Usuario B',
            esDesarrollador: false,
            agenciaId: 'agencia-b',
          ),
        );
    final segundo = container.read(repositorioProvider);

    expect(
      identical(primero, segundo),
      isFalse,
      reason:
          'Si el repositorio sobrevive al cambio de sesión, sus FutureProvider '
          'pueden mostrar durante unos instantes datos de la cuenta anterior.',
    );
  });
}
