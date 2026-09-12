# Mi Agencia

ERP para agencias de autos usados: stock, costos reales, márgenes ajustados por
inflación, embudo de interesados con semáforo crediticio del BCRA y email marketing.

Nace de un HTML monolítico con `localStorage` (preservado en
[`referencia/rotacion_original.html`](referencia/rotacion_original.html)) y se
convierte en una app multi-agencia con backend propio, para Windows y Android.

---

## Estado

| Pieza | Estado |
|---|---|
| Esquema multi-tenant (25 tablas, 6 vistas, 65 políticas RLS) | escrito y ejecutado contra Postgres; **falta aplicarlo en Supabase** |
| Motor de cálculo portado a SQL | **verificado**: 273 valores comparados contra el JS original, coincidencia total |
| Toolchain Flutter | instalado y funcionando |
| App: tema, shell, navegación, login | funcionando |
| App: panel, inventario, ficha, interesados | funcionando con datos reales del cliente |
| App: vehículos, gastos, precios, ventas, campañas, configuración, agencias | **pendientes** — la navegación existe y cada una explica en pantalla qué hará |
| APK Android | **compila** (release 51,5 MB) |
| Ejecutable de Windows | **no compila** — falta Visual Studio con C++ (requiere administrador) |
| Integración BCRA | endpoints verificados en vivo, Edge Function pendiente |
| Integración ArgAutos (valor de revista) | API verificada en vivo, falta la API key |
| Email marketing | tablas listas, falta elegir proveedor |

Todo lo que falta, con los pasos exactos, está en
[`docs/PENDIENTE.md`](docs/PENDIENTE.md).

## Arrancar

```powershell
.\scripts\dev.ps1 run -d chrome      # app en el navegador, con hot reload
.\scripts\dev.ps1 build apk --release
.\scripts\dev.ps1 test
```

Sin credenciales de Supabase la app arranca en **modo demo**, contra los datos
reales del sistema original del cliente cargados en memoria. Es lo que permite
recorrerla entera hoy, antes de que exista la base.

---

## Decisiones tomadas

**Flutter para Android y Windows.** Un solo código Dart para las dos plataformas.

**Las fórmulas financieras viven en SQL, no en la app.** `v_inventario` es el port
1:1 de `computeInventory()` del HTML original. El motivo es concreto: esas fórmulas
definen cuánta plata gana la agencia, y si viven en el cliente hay que reimplementarlas
por plataforma — cualquier divergencia se paga en pesos. La app lee la vista y muestra.
Lo único que sí se calcula en Dart son los simuladores interactivos (precio sugerido,
cuotas), porque son "qué pasaría si" que no se persisten.

**Aislamiento entre agencias en la base, no en la app.** Todas las tablas tienen RLS
y todas las vistas van con `security_invoker = on`. Sin eso una vista corre con los
permisos de su dueño y filtraría el inventario de todas las agencias a cualquier
usuario logueado.

**Cuenta de desarrollador = `perfiles.es_desarrollador`.** Es un rol de plataforma,
no de agencia: por eso no vive en `membresias`. Solo esa cuenta da de alta agencias.
Un trigger impide que alguien se lo auto-asigne aunque pase el RLS.

**Interesados separados en `clientes` + `oportunidades`.** El original tenía una sola
tabla. La persona se repite entre vehículos y entre años; el interés es por unidad.
Sin esa separación no hay email marketing ni semáforo crediticio posible, porque ambos
son propiedades de la persona.

**Catálogo de precios espejado, no consultado en vivo.** ArgAutos corta a 3 req/min
anónimo. Se replica su catálogo completo en nuestro Postgres una vez por mes.

---

## Los dos semáforos

Son cosas distintas y conviene no confundirlas:

- **Semáforo de rotación** (`v_inventario.alerta`): cuántos días lleva la unidad en
  stock contra los umbrales de la agencia. Verde → observar → atención → crítico.
- **Semáforo crediticio** (`v_clientes_semaforo.semaforo`): situación del interesado
  en la Central de Deudores del BCRA. Verde (situación 1-2), amarillo (situación 3,
  cheques rechazados ya pagados, o +30 días de atraso), rojo (situación 4-6, cheques
  impagos o proceso judicial).

---

## Estructura

```
mi-agencia/
├── app/                          # proyecto Flutter
│   └── lib/
│       ├── core/                 # tema, formato, router, sesión, config
│       ├── dominio/              # modelos y motor de cálculo
│       ├── datos/                # repositorio (demo y Supabase)
│       ├── ui/                   # componentes y shell adaptativo
│       └── funciones/            # una carpeta por pantalla
├── supabase/
│   ├── migrations/               # 0001..0010, se aplican en orden
│   ├── migraciones_completas.sql # las 10 en un archivo, para el SQL Editor
│   └── functions/                # Edge Functions (pendientes)
├── tests/                        # verificación del SQL contra el JS original
├── docs/
├── scripts/
│   ├── dev.ps1                   # entorno de desarrollo — usar siempre este
│   └── setup-flutter.ps1         # instalación del toolchain en D:
└── referencia/
    └── rotacion_original.html
```

### Migraciones

| Archivo | Qué define |
|---|---|
| `0001_extensiones_enums.sql` | extensiones y tipos enumerados |
| `0002_tenancy.sql` | agencias, perfiles, membresías, invitaciones |
| `0003_helpers_rls.sql` | funciones `security definer` que sostienen el RLS |
| `0004_catalogo_referencia.sql` | espejo de ArgAutos, serie IPC, cotizaciones |
| `0005_vehiculos.sql` | stock, fotos, gastos, cambios de precio, ventas |
| `0006_crm_bcra.sql` | clientes, oportunidades, interacciones, consultas BCRA |
| `0007_config_marketing.sql` | config por agencia, campañas, auditoría |
| `0008_motor_calculo.sql` | **el motor**: `v_inventario`, `v_dashboard`, evolución mensual |
| `0009_rls_policies.sql` | políticas RLS y permisos de Storage |
| `0010_seed_referencia.sql` | serie IPC del INDEC y cotizaciones iniciales |

---

## APIs externas

| Servicio | Para qué | Costo | Estado |
|---|---|---|---|
| [BCRA Central de Deudores](https://api.bcra.gob.ar) | semáforo crediticio del interesado | gratis, sin key | verificado |
| [ArgAutos](https://argautos.com) | valor de revista (6.163 versiones) | gratis con key | verificado |
| BCRA Estadísticas | cotización del dólar | gratis, sin key | por integrar |
| Resend o Brevo | envío de campañas | free tier | a definir |

El BCRA no manda cabeceras CORS y ArgAutos limita por IP: las dos se consumen desde
Edge Functions, nunca desde la app.
