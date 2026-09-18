import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../dominio/alta_vehiculo.dart';
import '../dominio/alta_interesado.dart';
import '../dominio/agencias.dart';
import '../dominio/bcra.dart';
import '../dominio/campanas.dart';
import '../dominio/gastos.dart';
import '../dominio/precios.dart';
import '../dominio/ventas.dart';
import '../dominio/modelos.dart';
import 'repositorio.dart';

/// Lectura contra la base real.
///
/// Las pantallas no saben que esto existe: hablan con [Repositorio]. Por eso
/// pasar de modo demo a base real no toca una sola linea de UI.
///
/// RLS controla el acceso. Los filtros de agencia delimitan la vista de
/// trabajo, especialmente para usuarios con acceso a más de una agencia.
class RepositorioSupabase implements Repositorio {
  const RepositorioSupabase();

  SupabaseClient get _db => Supabase.instance.client;

  @override
  Future<List<VehiculoInventario>> inventario({
    int desde = 0,
    int cantidad = 500,
  }) async {
    final filas = await _db
        .from('v_inventario')
        .select()
        .eq('agencia_id', await _miAgencia())
        .order('dias_en_stock', ascending: false)
        .range(desde, desde + cantidad - 1);

    return filas.map(_aVehiculo).toList();
  }

  @override
  Future<ConfigAgencia> config() async {
    final fila = await _db
        .from('agencia_config')
        .select()
        .limit(1)
        .maybeSingle();
    if (fila == null) return const ConfigAgencia();

    // El tipo de cambio no vive en agencia_config: la config solo elige CUAL
    // usar, y la cotizacion en si es un dato publico compartido.
    final tipo = fila['tipo_cambio_preferido'] as String? ?? 'oficial';
    final cotizacion = await _db
        .from('cotizaciones')
        .select('venta')
        .eq('tipo', tipo)
        .order('fecha', ascending: false)
        .limit(1)
        .maybeSingle();

    return ConfigAgencia(
      diasVerde: _entero(fila['dias_verde']) ?? 30,
      diasAmarillo: _entero(fila['dias_amarillo']) ?? 60,
      diasRojo: _entero(fila['dias_rojo']) ?? 90,
      margenMinimo: _decimal(fila['margen_minimo']) ?? 0.10,
      margenObjetivo: _decimal(fila['margen_objetivo']) ?? 0.30,
      toleranciaCaidaMargen: _decimal(fila['tolerancia_caida_margen']) ?? 0.005,
      toleranciaDesvioPrecio:
          _decimal(fila['tolerancia_desvio_precio']) ?? 0.02,
      umbralGastosAltos: _decimal(fila['umbral_gastos_altos']) ?? 1000000,
      redondeo: _decimal(fila['redondeo']) ?? 50000,
      capacidad: _entero(fila['capacidad']) ?? 60,
      tasaFinanciacionMensual:
          _decimal(fila['tasa_financiacion_mensual']) ?? 0.06,
      tipoCambio: _decimal(cotizacion?['venta']) ?? 1,
    );
  }

  @override
  Future<List<Interesado>> interesados({String? oportunidadId}) async {
    // Una sola ida y vuelta: PostgREST resuelve las relaciones anidadas.
    // Se trae TODO lo que la agencia sabe de la persona porque es lo que
    // despues se imprime en el informe crediticio, y volver a la base en el
    // medio de armar un PDF seria pedirlo dos veces por nada.
    var consulta = _db
        .from('oportunidades')
        .select('''
          id, estado, interes, notas, created_at,
          presupuesto_max, necesita_financiacion,
          entrega_usado, usado_descripcion, usado_valor_estimado,
          proxima_accion, proxima_accion_fecha,
          clientes!inner (
            id, nombre, apellido, cuit, dni, email, telefono, whatsapp,
            localidad, provincia, origen, notas, acepta_marketing
          ),
          vehiculos ( id, codigo, marca, modelo, anio, precio_objetivo )
        ''')
        .eq('agencia_id', await _miAgencia())
        .isFilter('clientes.deleted_at', null);
    if (oportunidadId != null) consulta = consulta.eq('id', oportunidadId);
    final filas = await consulta
        .order('created_at', ascending: false)
        .limit(500);

    if (filas.isEmpty) return const [];

    // El semaforo se resuelve aparte porque vive en una vista y PostgREST no
    // puede unirla dentro del mismo select anidado.
    final idsClientes = filas
        .map((f) => (f['clientes'] as Map)['id'] as String)
        .toSet()
        .toList();

    final semaforos = await _db
        .from('v_clientes_semaforo')
        .select()
        .inFilter('cliente_id', idsClientes);

    final porCliente = {
      for (final s in semaforos) s['cliente_id'] as String: s,
    };

    return filas.map((f) {
      final cliente = f['clientes'] as Map<String, dynamic>;
      final vehiculo = f['vehiculos'] as Map<String, dynamic>?;

      return Interesado(
        id: f['id'] as String,
        clienteId: cliente['id'] as String,
        nombre: [
          cliente['nombre'],
          cliente['apellido'],
        ].whereType<String>().where((s) => s.isNotEmpty).join(' '),
        telefono: cliente['telefono'] as String?,
        whatsapp: cliente['whatsapp'] as String?,
        email: cliente['email'] as String?,
        cuit: cliente['cuit'] as String?,
        dni: cliente['dni'] as String?,
        localidad: cliente['localidad'] as String?,
        provincia: cliente['provincia'] as String?,
        origen: cliente['origen'] as String?,
        aceptaMarketing: cliente['acepta_marketing'] != false,
        vehiculoId: vehiculo?['id'] as String?,
        vehiculoCodigo: vehiculo?['codigo'] as String?,
        vehiculoTitulo: vehiculo == null
            ? null
            : '${vehiculo['marca']} ${vehiculo['modelo']}',
        vehiculoPrecio: _decimal(vehiculo?['precio_objetivo']),
        estadoOportunidad: f['estado'] as String?,
        interes: _entero(f['interes']),
        presupuestoMax: _decimal(f['presupuesto_max']),
        necesitaFinanciacion: f['necesita_financiacion'] == true,
        entregaUsado: f['entrega_usado'] == true,
        usadoDescripcion: f['usado_descripcion'] as String?,
        usadoValorEstimado: _decimal(f['usado_valor_estimado']),
        proximaAccion: f['proxima_accion'] as String?,
        proximaAccionFecha: _fecha(f['proxima_accion_fecha']),
        notas: f['notas'] as String?,
        notasCliente: cliente['notas'] as String?,
        fecha: _fecha(f['created_at']),
        consulta: _aConsulta(porCliente[cliente['id']]),
      );
    }).toList();
  }

  /// Arma la consulta a partir de una fila de `v_clientes_semaforo`.
  ///
  /// Devuelve null cuando a la persona nunca se le consulto el BCRA. Ese caso
  /// no es "situacion desconocida por error": es que nadie pregunto todavia,
  /// y la pantalla lo tiene que decir distinto.
  static ConsultaBcra? _aConsulta(Map<String, dynamic>? fila) {
    if (fila == null || fila['consultado_at'] == null) return null;
    return ConsultaBcra.desdeJson(fila);
  }

  @override
  Future<Interesado> crearInteresado(AltaInteresado alta) async {
    alta.validar();
    final r = await _db.rpc(
      'crear_interesado',
      params: {
        'p_agencia': await _miAgencia(),
        'p_solicitud': alta.solicitud,
        'p_datos': alta.json,
      },
    );
    // Relee la persona real: un CUIT existente no se sobrescribe con el alta.
    return (await interesados(oportunidadId: r['id'] as String)).single;
  }

  @override
  Future<void> eliminarInteresado(Interesado interesado) async {
    // Los objetos se quitan primero: la política de Storage valida que la
    // oportunidad todavía exista. Después, la función borra las filas en una
    // sola transacción y conserva al cliente si tiene otra oportunidad.
    final carpeta = await _carpetaInforme(interesado);
    final archivos = await _db.storage.from('informes').list(path: carpeta);
    final rutas = [for (final archivo in archivos) '$carpeta/${archivo.name}'];
    if (rutas.isNotEmpty) {
      await _db.storage.from('informes').remove(rutas);
    }
    await _db.rpc(
      'eliminar_interesado',
      params: {'p_oportunidad': interesado.id},
    );
  }

  Future<String> _carpetaInforme(Interesado i) async =>
      '${await _miAgencia()}/${i.clienteId}/${i.id}';

  @override
  Future<void> guardarInforme(Interesado interesado, List<int> bytes) async {
    final fecha = interesado.consulta?.consultadoEl.microsecondsSinceEpoch;
    final ruta =
        '${await _carpetaInforme(interesado)}/${fecha ?? 'sin-consulta'}.pdf';
    await _db.storage
        .from('informes')
        .uploadBinary(
          ruta,
          Uint8List.fromList(bytes),
          fileOptions: const FileOptions(
            contentType: 'application/pdf',
            upsert: true,
          ),
        );
  }

  @override
  Future<List<InformeGuardado>> informes(Interesado interesado) async {
    final carpeta = await _carpetaInforme(interesado);
    final archivos = await _db.storage
        .from('informes')
        .list(
          path: carpeta,
          searchOptions: const SearchOptions(
            sortBy: SortBy(column: 'name', order: 'desc'),
          ),
        );
    return [
      for (final a in archivos.where((a) => a.name.endsWith('.pdf')))
        InformeGuardado(
          ruta: '$carpeta/${a.name}',
          fecha:
              DateTime.tryParse(a.updatedAt ?? a.createdAt ?? '') ??
              DateTime.now(),
        ),
    ];
  }

  @override
  Future<List<int>> descargarInforme(String ruta) =>
      _db.storage.from('informes').download(ruta);

  @override
  Future<void> guardarCuit({
    required String clienteId,
    required String cuit,
  }) async {
    final limpio = cuit.replaceAll(RegExp(r'\D'), '');
    if (!cuitValido(limpio)) {
      throw Exception('Ese CUIT/CUIL no es valido. Revisa los 11 digitos.');
    }
    await _db.from('clientes').update({'cuit': limpio}).eq('id', clienteId);
  }

  @override
  Future<ConsultaBcra> consultarBcra({
    required String clienteId,
    required String cuit,
    bool forzar = false,
  }) async {
    final limpio = cuit.replaceAll(RegExp(r'\D'), '');

    // Se valida aca ademas de en el servidor. No es redundancia inutil: un
    // CUIT mal tipeado le da 404 el BCRA, y un 404 significa "sin deudas".
    // Sin esta validacion, un digito de mas pinta de verde a cualquiera.
    if (!cuitValido(limpio)) {
      throw Exception('Ese CUIT/CUIL no es valido. Revisa los 11 digitos.');
    }

    late FunctionResponse r;
    try {
      r = await _db.functions.invoke(
        'bcra-consulta',
        body: {'cliente_id': clienteId, 'cuit': limpio, 'forzar': forzar},
      );
    } on FunctionException catch (e) {
      final detalle = e.details;
      throw Exception(
        detalle is Map && detalle['error'] != null
            ? detalle['error']
            : 'No se pudo consultar el BCRA. Reintentá en unos minutos.',
      );
    }

    final datos = r.data;
    if (datos is! Map) {
      throw Exception('El servidor no devolvio una respuesta entendible.');
    }
    if (datos['error'] != null) throw Exception(datos['error'].toString());

    final consulta = datos['consulta'];
    if (consulta is! Map) {
      throw Exception('El servidor no devolvio la consulta.');
    }

    return ConsultaBcra.desdeJson(
      consulta.cast<String, dynamic>(),
      cacheada: datos['cacheada'] == true,
    );
  }

  // -------------------------------------------------------------------
  // Escritura
  // -------------------------------------------------------------------

  /// La agencia del usuario. Se resuelve en la base y no se guarda en el
  /// cliente: si viniera del cliente, bastaria con editarlo para escribir en
  /// la agencia de otro. El RLS lo rechazaria igual, pero mejor no llegar.
  Future<String> _miAgencia() async {
    final fila = await _db
        .from('membresias')
        .select('agencia_id')
        .eq('usuario_id', _db.auth.currentUser?.id ?? '')
        .eq('activa', true)
        .order('agencia_id')
        .limit(1)
        .maybeSingle();
    if (fila == null) {
      throw Exception(
        'Tu usuario no está asignado a ninguna agencia. '
        'Pedile al administrador que te dé acceso.',
      );
    }
    return fila['agencia_id'] as String;
  }

  @override
  Future<String> siguienteCodigo() async {
    final agencia = await _miAgencia();
    final r = await _db.rpc<String>(
      'siguiente_codigo_vehiculo',
      params: {'p_agencia': agencia},
    );
    return r;
  }

  @override
  Future<String> crearVehiculo(AltaVehiculo v) async {
    final agencia = await _miAgencia();
    final fila = await _db
        .from('vehiculos')
        .insert({
          'agencia_id': agencia,
          'codigo': v.codigo ?? await siguienteCodigo(),
          ..._camposEditables(v),
        })
        .select('id')
        .single();
    return fila['id'] as String;
  }

  @override
  Future<void> actualizarVehiculo(AltaVehiculo v) async {
    if (v.id == null) throw ArgumentError('Falta el id del vehiculo a editar.');
    await _db.from('vehiculos').update(_camposEditables(v)).eq('id', v.id!);
  }

  @override
  Future<void> eliminarVehiculo(String id) async {
    // Baja logica: la unidad desaparece del inventario pero conserva su
    // historial de gastos, precios y ventas. Borrarla de verdad se llevaria
    // por cascada la trazabilidad de operaciones ya cerradas.
    await _db
        .from('vehiculos')
        .update({'deleted_at': DateTime.now().toIso8601String()})
        .eq('id', id);
  }

  @override
  Future<List<Gasto>> gastos({String? vehiculoId}) async {
    var consulta = _db.from('gastos').select('''
          id, vehiculo_id, fecha, categoria, descripcion, importe, proveedor,
          vehiculos!inner ( codigo, marca, modelo )
        ''');

    if (vehiculoId != null) consulta = consulta.eq('vehiculo_id', vehiculoId);

    final filas = await consulta.order('fecha', ascending: false).limit(500);

    return filas.map((f) {
      final v = f['vehiculos'] as Map<String, dynamic>?;
      return Gasto(
        id: f['id'] as String,
        vehiculoId: f['vehiculo_id'] as String,
        fecha: _fecha(f['fecha']) ?? DateTime.now(),
        categoria: CategoriaGasto.desde(f['categoria'] as String?),
        importe: _decimal(f['importe']) ?? 0,
        descripcion: f['descripcion'] as String?,
        proveedor: f['proveedor'] as String?,
        vehiculoCodigo: v?['codigo'] as String?,
        vehiculoTitulo: v == null ? null : '${v['marca']} ${v['modelo']}',
      );
    }).toList();
  }

  @override
  Future<void> crearGasto(AltaGasto g) async {
    final agencia = await _miAgencia();
    await _db.from('gastos').insert({
      'agencia_id': agencia,
      'vehiculo_id': g.vehiculoId,
      'fecha': _soloFecha(g.fecha!),
      'categoria': g.categoria.valorBd,
      'descripcion': _oNulo(g.descripcion),
      'proveedor': _oNulo(g.proveedor),
      'importe': g.importe,
    });
  }

  @override
  Future<void> eliminarGasto(String id) async {
    // Los gastos si se borran de verdad: a diferencia de una unidad, un gasto
    // mal cargado no tiene historial que preservar, y dejarlo marcado como
    // borrado obligaria a filtrarlo en cada suma del motor de calculo.
    await _db.from('gastos').delete().eq('id', id);
  }

  @override
  Future<List<CambioPrecio>> cambiosPrecio({String? vehiculoId}) async {
    var consulta = _db.from('cambios_precio').select('''
          id, vehiculo_id, fecha, precio_anterior, precio_nuevo, motivo,
          vehiculos!inner ( codigo, marca, modelo )
        ''');

    if (vehiculoId != null) consulta = consulta.eq('vehiculo_id', vehiculoId);

    final filas = await consulta.order('fecha', ascending: false).limit(500);

    return filas.map((f) {
      final v = f['vehiculos'] as Map<String, dynamic>?;
      return CambioPrecio(
        id: f['id'] as String,
        vehiculoId: f['vehiculo_id'] as String,
        fecha: _fecha(f['fecha']) ?? DateTime.now(),
        precioNuevo: _decimal(f['precio_nuevo']) ?? 0,
        precioAnterior: _decimal(f['precio_anterior']),
        motivo: f['motivo'] as String?,
        vehiculoCodigo: v?['codigo'] as String?,
        vehiculoTitulo: v == null ? null : '${v['marca']} ${v['modelo']}',
      );
    }).toList();
  }

  @override
  Future<void> crearCambioPrecio(AltaPrecio p) async {
    final agencia = await _miAgencia();
    // precio_anterior NO se manda: lo completa un trigger leyendo el ultimo
    // precio vigente. Calcularlo en el cliente abre la puerta a que dos
    // vendedores guarden a la vez y uno pise el historial del otro.
    await _db.from('cambios_precio').insert({
      'agencia_id': agencia,
      'vehiculo_id': p.vehiculoId,
      'fecha': _soloFecha(p.fecha!),
      'precio_nuevo': p.precioNuevo,
      'motivo': _oNulo(p.motivo),
    });
  }

  @override
  Future<List<Venta>> ventas() async {
    final filas = await _db
        .from('ventas')
        .select('''
          id, vehiculo_id, fecha_venta, precio_final, gastos_finales,
          forma_pago, cuotas, observaciones,
          vehiculos!inner ( codigo, marca, modelo )
        ''')
        .order('fecha_venta', ascending: false)
        .limit(500);

    if (filas.isEmpty) return const [];

    // Los costos y el ajuste por IPC los calcula la vista, no la app.
    final ids = filas.map((f) => f['vehiculo_id'] as String).toList();
    final calculados = await _db
        .from('v_inventario')
        .select('id, costo_total, costo_total_hoy, dias_en_stock, tipo_cambio')
        .inFilter('id', ids);

    final porId = {for (final c in calculados) c['id'] as String: c};

    return filas.map((f) {
      final v = f['vehiculos'] as Map<String, dynamic>?;
      final c = porId[f['vehiculo_id']];
      return Venta(
        id: f['id'] as String,
        vehiculoId: f['vehiculo_id'] as String,
        fechaVenta: _fecha(f['fecha_venta']) ?? DateTime.now(),
        precioFinal: _decimal(f['precio_final']) ?? 0,
        gastosFinales: _decimal(f['gastos_finales']) ?? 0,
        formaPago: f['forma_pago'] as String?,
        cuotas: _entero(f['cuotas']),
        observaciones: f['observaciones'] as String?,
        vehiculoCodigo: v?['codigo'] as String?,
        vehiculoTitulo: v == null ? null : '${v['marca']} ${v['modelo']}',
        costoTotal: _decimal(c?['costo_total']),
        costoTotalHoy: _decimal(c?['costo_total_hoy']),
        diasEnStock: _entero(c?['dias_en_stock']),
        tipoCambio: _decimal(c?['tipo_cambio']),
      );
    }).toList();
  }

  @override
  Future<void> crearVenta(AltaVenta v) async {
    final agencia = await _miAgencia();
    // El estado del vehiculo no se toca desde aca: un trigger lo pasa a
    // vendido. Y la unicidad de vehiculo_id impide venderlo dos veces.
    await _db.from('ventas').insert({
      'agencia_id': agencia,
      'vehiculo_id': v.vehiculoId,
      'fecha_venta': _soloFecha(v.fechaVenta!),
      'precio_final': v.precioFinal,
      'gastos_finales': v.gastosFinales,
      'forma_pago': v.formaPago.etiqueta,
      'cuotas': v.pideCuotas ? v.cuotas : null,
      'observaciones': _oNulo(v.observaciones),
    });
  }

  @override
  Future<Agencia?> miAgencia() async {
    final fila = await _db
        .from('agencias')
        .select(
          'id, nombre, slug, activa, plan, cuit, email_contacto, telefono, '
          'localidad, provincia, vigente_hasta, created_at',
        )
        .eq('id', await _miAgencia())
        .limit(1)
        .maybeSingle();
    if (fila == null) return null;

    return Agencia(
      id: fila['id'] as String,
      nombre: fila['nombre'] as String,
      slug: fila['slug'] as String,
      activa: fila['activa'] as bool? ?? true,
      plan: fila['plan'] as String? ?? 'basico',
      cuit: fila['cuit'] as String?,
      emailContacto: fila['email_contacto'] as String?,
      telefono: fila['telefono'] as String?,
      localidad: fila['localidad'] as String?,
      provincia: fila['provincia'] as String?,
      vigenteHasta: _fecha(fila['vigente_hasta']),
      creadaEl: _fecha(fila['created_at']),
    );
  }

  @override
  Future<void> guardarDatosAgencia(DatosAgencia d) async {
    final agencia = await _miAgencia();

    // Plan, vencimiento, slug y estado no se mandan. No es solo que el
    // trigger los revierta: mandarlos daria a entender que se pueden cambiar
    // desde aca, y no es asi por diseno.
    await _db
        .from('agencias')
        .update({
          'nombre': d.nombre.trim(),
          'cuit': d.cuitLimpio.isEmpty ? null : d.cuitLimpio,
          'email_contacto': _oNulo(d.emailContacto),
          'telefono': _oNulo(d.telefono),
          'localidad': _oNulo(d.localidad),
          'provincia': _oNulo(d.provincia),
        })
        .eq('id', agencia);
  }

  @override
  Future<void> guardarConfig(ConfigAgencia c) async {
    final agencia = await _miAgencia();
    await _db
        .from('agencia_config')
        .update({
          'dias_verde': c.diasVerde,
          'dias_amarillo': c.diasAmarillo,
          'dias_rojo': c.diasRojo,
          'margen_minimo': c.margenMinimo,
          'margen_objetivo': c.margenObjetivo,
          'umbral_gastos_altos': c.umbralGastosAltos,
          'redondeo': c.redondeo,
          'capacidad': c.capacidad,
          'tasa_financiacion_mensual': c.tasaFinanciacionMensual,
        })
        .eq('agencia_id', agencia);
  }

  // -------------------------------------------------------------------
  // Administracion de agencias (solo la cuenta de desarrollador)
  //
  // No hace falta chequear el rol aca: el RLS solo deja insertar agencias a
  // quien tiene es_desarrollador, y un select de un usuario comun devuelve
  // unicamente las suyas. Filtrar en el cliente seria seguridad de mentira.
  // -------------------------------------------------------------------

  @override
  Future<List<Agencia>> agencias() async {
    final filas = await _db
        .from('agencias')
        .select('''
          id, nombre, slug, activa, plan, cuit, email_contacto, telefono,
          localidad, provincia, vigente_hasta, created_at,
          membresias ( id ), vehiculos ( id )
        ''')
        .order('created_at', ascending: false);

    return filas.map((f) {
      // PostgREST devuelve las relaciones como listas: se cuentan, no se leen.
      final miembros = (f['membresias'] as List?)?.length ?? 0;
      final unidades = (f['vehiculos'] as List?)?.length ?? 0;
      return Agencia(
        id: f['id'] as String,
        nombre: f['nombre'] as String,
        slug: f['slug'] as String,
        activa: f['activa'] as bool? ?? true,
        plan: f['plan'] as String? ?? 'basico',
        cuit: f['cuit'] as String?,
        emailContacto: f['email_contacto'] as String?,
        telefono: f['telefono'] as String?,
        localidad: f['localidad'] as String?,
        provincia: f['provincia'] as String?,
        vigenteHasta: _fecha(f['vigente_hasta']),
        creadaEl: _fecha(f['created_at']),
        miembros: miembros,
        vehiculos: unidades,
      );
    }).toList();
  }

  @override
  Future<String> crearAgencia(AltaAgencia a) async {
    final fila = await _db
        .from('agencias')
        .insert({
          'nombre': a.nombre.trim(),
          'slug': a.slug,
          'cuit': a.cuitLimpio.isEmpty ? null : a.cuitLimpio,
          'email_contacto': _oNulo(a.emailContacto),
          'telefono': _oNulo(a.telefono),
          'localidad': _oNulo(a.localidad),
          'provincia': _oNulo(a.provincia),
          'plan': a.plan,
          'vigente_hasta': a.vigenteHasta == null
              ? null
              : _soloFecha(a.vigenteHasta!),
          'creada_por': _db.auth.currentUser?.id,
        })
        .select('id')
        .single();

    final id = fila['id'] as String;

    // La invitacion se resuelve sola: cuando esa persona se registre con ese
    // email, el trigger de auth.users la convierte en membresia de owner.
    await _db.from('invitaciones').insert({
      'agencia_id': id,
      'email': a.emailDueno.trim(),
      'rol': 'owner',
      'invitado_por': _db.auth.currentUser?.id,
    });

    return id;
  }

  @override
  Future<void> cambiarEstadoAgencia(String id, {required bool activa}) async {
    await _db.from('agencias').update({'activa': activa}).eq('id', id);
  }

  @override
  Future<List<Invitacion>> invitacionesPendientes() async {
    final filas = await _db
        .from('invitaciones')
        .select('id, email, rol, expira_at, agencias ( nombre )')
        .isFilter('aceptada_at', null)
        .order('created_at', ascending: false);

    return filas.map((f) {
      final a = f['agencias'] as Map<String, dynamic>?;
      return Invitacion(
        id: f['id'] as String,
        email: f['email'] as String,
        rol: RolMembresia.desde(f['rol'] as String?),
        expiraEl: _fecha(f['expira_at']) ?? DateTime.now(),
        agenciaNombre: a?['nombre'] as String?,
      );
    }).toList();
  }

  @override
  Future<List<Campana>> campanas() async {
    final filas = await _db
        .from('campanas')
        .select('''
          id, nombre, asunto, cuerpo_html, estado, total_destinatarios,
          total_enviados, total_aperturas, total_clicks, enviada_at, created_at
        ''')
        .order('created_at', ascending: false)
        .limit(200);

    return filas
        .map(
          (f) => Campana(
            id: f['id'] as String,
            nombre: f['nombre'] as String,
            asunto: f['asunto'] as String,
            estado: EstadoCampana.desde(f['estado'] as String?),
            cuerpoHtml: f['cuerpo_html'] as String? ?? '',
            destinatarios: _entero(f['total_destinatarios']) ?? 0,
            enviados: _entero(f['total_enviados']) ?? 0,
            aperturas: _entero(f['total_aperturas']) ?? 0,
            clicks: _entero(f['total_clicks']) ?? 0,
            enviadaEl: _fecha(f['enviada_at']),
            creadaEl: _fecha(f['created_at']),
          ),
        )
        .toList();
  }

  @override
  Future<String> crearCampana(AltaCampana c) async {
    final agencia = await _miAgencia();
    final fila = await _db
        .from('campanas')
        .insert({
          'agencia_id': agencia,
          'nombre': c.nombre.trim(),
          'asunto': c.asunto.trim(),
          'cuerpo_html': c.html,
          'estado': 'borrador',
          'created_by': _db.auth.currentUser?.id,
        })
        .select('id')
        .single();
    return fila['id'] as String;
  }

  @override
  Future<int> destinatariosPosibles() async {
    // Los que pidieron la baja no entran, y eso no es negociable: el filtro
    // vive tanto aca como en la Edge Function.
    final filas = await _db
        .from('clientes')
        .select('id')
        .eq('acepta_marketing', true)
        .not('email', 'is', null)
        .isFilter('deleted_at', null);
    return filas.length;
  }

  @override
  Future<int> enviarCampana(String campanaId) async {
    // El envio lo hace el servidor: la API key de Resend no puede viajar
    // dentro de la app, y Resend tampoco manda cabeceras CORS.
    final r = await _db.functions.invoke(
      'enviar-campana',
      body: {'campana_id': campanaId},
    );

    final datos = r.data;
    if (datos is Map && datos['error'] != null) {
      throw Exception(datos['error'].toString());
    }
    if (datos is Map && datos['enviados'] is int) {
      return datos['enviados'] as int;
    }
    return 0;
  }

  /// Solo lo que el usuario carga. Todo lo demas (costos, margenes, dias en
  /// stock) lo deriva la base: mandarlo desde el cliente seria pisar el motor
  /// de calculo con numeros de dudosa procedencia.
  static Map<String, dynamic> _camposEditables(AltaVehiculo v) => {
    'marca': v.marca.trim(),
    'modelo': v.modelo.trim(),
    'anio': v.anio,
    'version': _oNulo(v.version),
    'km': v.km,
    'patente': _oNulo(v.patente)?.toUpperCase(),
    'fecha_compra': _soloFecha(v.fechaCompra!),
    'fecha_ingreso': _soloFecha(v.fechaIngreso!),
    'precio_compra': v.precioCompra,
    'precio_objetivo': v.precioObjetivo,
    'estado': _deEstado(v.estado),
    'observaciones': _oNulo(v.observaciones),
  };

  static String? _oNulo(String s) => s.trim().isEmpty ? null : s.trim();

  /// La columna es `date`: mandar un timestamp con hora hace que Postgres lo
  /// trunque segun zona horaria y la fecha se puede correr un dia.
  static String _soloFecha(DateTime f) =>
      '${f.year.toString().padLeft(4, '0')}-'
      '${f.month.toString().padLeft(2, '0')}-'
      '${f.day.toString().padLeft(2, '0')}';

  static String _deEstado(EstadoVehiculo e) => switch (e) {
    EstadoVehiculo.enStock => 'en_stock',
    EstadoVehiculo.enPreparacion => 'en_preparacion',
    EstadoVehiculo.reservado => 'reservado',
    EstadoVehiculo.vendido => 'vendido',
    EstadoVehiculo.dadoDeBaja => 'dado_de_baja',
  };

  // -------------------------------------------------------------------
  // Conversores
  //
  // Postgres devuelve numeric como STRING en JSON, para no perder precision.
  // Si se castea directo a double explota en runtime, y encima solo con
  // ciertos valores: es el tipo de bug que aparece recien en produccion.
  // -------------------------------------------------------------------

  static double? _decimal(dynamic v) => switch (v) {
    null => null,
    final num n => n.toDouble(),
    final String s => double.tryParse(s),
    _ => null,
  };

  static int? _entero(dynamic v) => switch (v) {
    null => null,
    final int n => n,
    final num n => n.round(),
    final String s => int.tryParse(s) ?? double.tryParse(s)?.round(),
    _ => null,
  };

  static DateTime? _fecha(dynamic v) =>
      v == null ? null : DateTime.tryParse(v as String);

  static EstadoVehiculo _aEstado(String? s) => switch (s) {
    'en_stock' => EstadoVehiculo.enStock,
    'en_preparacion' => EstadoVehiculo.enPreparacion,
    'reservado' => EstadoVehiculo.reservado,
    'vendido' => EstadoVehiculo.vendido,
    'dado_de_baja' => EstadoVehiculo.dadoDeBaja,
    _ => EstadoVehiculo.enStock,
  };

  static VehiculoInventario _aVehiculo(Map<String, dynamic> f) {
    return VehiculoInventario(
      id: f['id'] as String,
      codigo: f['codigo'] as String,
      marca: f['marca'] as String,
      modelo: f['modelo'] as String,
      anio: _entero(f['anio']) ?? 0,
      version: f['version'] as String?,
      km: _entero(f['km']),
      estado: _aEstado(f['estado'] as String?),
      alerta: AlertaRotacion.desde(f['alerta'] as String? ?? 'normal'),
      fechaIngreso: _fecha(f['fecha_ingreso']) ?? DateTime.now(),
      fechaCompra: _fecha(f['fecha_compra']),
      patente: f['patente'] as String?,
      precioCompra: _decimal(f['precio_compra']) ?? 0,
      precioObjetivo: _decimal(f['precio_objetivo']) ?? 0,
      gastosAcum: _decimal(f['gastos_acum']) ?? 0,
      cantidadGastos: _entero(f['cantidad_gastos']) ?? 0,
      costoTotal: _decimal(f['costo_total']) ?? 0,
      diasEnStock: _entero(f['dias_en_stock']) ?? 0,
      precioActual: _decimal(f['precio_actual']) ?? 0,
      capitalInmovilizado: _decimal(f['capital_inmovilizado']) ?? 0,
      gananciaEstimada: _decimal(f['ganancia_estimada']) ?? 0,
      margenActual: _decimal(f['margen_actual']) ?? 0,
      margenEsperado: _decimal(f['margen_esperado']) ?? 0,
      margenReal: _decimal(f['margen_real']),
      precioParaMargenObjetivo: _decimal(f['precio_para_margen_objetivo']) ?? 0,
      precioSugerido: _decimal(f['precio_sugerido']) ?? 0,
      costoTotalHoy: _decimal(f['costo_total_hoy']) ?? 0,
      gananciaRealIpc: _decimal(f['ganancia_real_ipc']) ?? 0,
      gananciaRealUsd: _decimal(f['ganancia_real_usd']) ?? 0,
      fechaVenta: _fecha(f['fecha_venta']),
      precioFinal: _decimal(f['precio_final']),
      observaciones: f['observaciones'] as String?,
      revistaArs: _decimal(f['revista_ars']),
    );
  }
}
