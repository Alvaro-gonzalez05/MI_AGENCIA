# Auditoría de flujos y respuesta visual

Fecha: 18/09/2026

## Criterio común

- Las altas y guardados muestran una confirmación flotante animada.
- Las acciones irreversibles abren el mismo diálogo con entrada suave, texto
  concreto y botón rojo cuando corresponde.
- Los botones quedan deshabilitados y muestran progreso mientras esperan al
  servidor, para evitar envíos dobles.
- Las animaciones se anulan cuando el sistema tiene activado “reducir
  movimiento”.
- Una pantalla vacía ofrece una sola acción principal. El botón flotante
  aparece recién cuando ya existe contenido.
- Cambiar de cuenta descarta todo el caché de negocio antes de cargar la nueva
  agencia.

## Flujos recorridos

| Sección | Acciones revisadas | Resultado |
| --- | --- | --- |
| Login | mostrar contraseña, ingresar, errores, salir | Conectado a Supabase; el cambio de cuenta vacía el caché anterior |
| Panel | métricas, accesos a inventario | Sin datos devuelve ceros válidos; tarjetas con respuesta al hover/toque |
| Inventario | filtros, búsqueda, ficha, simuladores | Navegación sin superposición y estados vacíos claros |
| Interesados | alta por pasos, volver, BCRA, PDF, ficha | Alta real, semáforo verde, consulta BCRA y PDF privado verificados |
| Vehículos | alta, edición, ficha, baja | Un solo alta visible; baja lógica con confirmación y conservación de historial |
| Gastos | alta, impacto en margen, eliminación | Un solo alta visible; borrado definitivo con importe y unidad en el aviso |
| Precios | cambio y validación | Un solo alta visible en cuenta vacía; historial actualiza inventario |
| Ventas | registro y validación | Un solo alta visible; al guardar, la unidad sale del stock |
| Campañas | borrador y envío | Guardado confirmado; envío pide confirmación con destinatarios |
| Configuración | parámetros y datos de agencia | Guardado confirmado y recálculo de proveedores derivados |
| Agencias | alta, suspensión, reactivación | Suspensión y reactivación comparten confirmación y respuesta de éxito |

## Regresiones automatizadas

- Cuenta vacía a 360 × 780 y 1440 × 900.
- Una sola acción de alta en Gastos, Precios, Ventas y Campañas.
- Baja de vehículo: cancelar no escribe; confirmar ejecuta una vez.
- Borrado de gasto: cancelar no escribe; confirmar ejecuta una vez.
- Diálogos destructivos sin desbordes en ancho angosto.
- Cambio de usuario reconstruye el repositorio y descarta datos en memoria.
- Alta de interesado, CUIT, BCRA, semáforo e informe PDF.
- Transiciones entre secciones sin pintar dos pantallas superpuestas.
