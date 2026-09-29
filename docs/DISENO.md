# El sistema de diseño "Clarity Drive"

Viene del diseño que entregó el cliente (export de Stitch, 28/09/2026:
`DESIGN.md`, `code.html` y la captura de la pantalla de Clientes). Este
documento dice dónde vive cada cosa en el código, para que la próxima
pantalla salga igual sin tener que adivinar.

El primer zip traía una sola pantalla (Clientes) y de ahí salieron los
tokens y los componentes. El segundo (28/09/2026) trajo **16 pantallas**, y
con eso se rehicieron Inicio, Inventario, Ficha del auto, Clientes,
Estadísticas y Simulador, más las preferencias de "Más".

**Lo que todavía no está**, porque necesita datos que la app no guarda:
fotos de las unidades, reservas, tareas y agenda, papeles y vencimientos,
cuotas y cobranzas, el precio de revista (ArgAutos) y usuarios y permisos.
En las pantallas donde el diseño los muestra, el lugar está hecho y dice
qué falta, en vez de fingir que no va nada.

## Qué cambió, en una línea

| Antes | Ahora |
|---|---|
| Tema oscuro por defecto | **Claro por defecto** (fondo papel `#FCF9F8`), oscuro en el menú "Más" |
| IBM Plex Sans | **Atkinson Hyperlegible Next** para leer, **Work Sans** para títulos |
| Texto base 13,5 px, etiquetas de 10 a 12 | **Base 15-16 px, nada por debajo de 13**, datos importantes 16+ |
| Botones y chips en píldora | **Rectángulos redondeados** (12 px), alto mínimo 52 |
| Tarjetas con sombra difusa | **Borde de 1,5 px** (2 px al pasar el mouse) y sombra corta |
| Filtros activos en ámbar | **Pestaña oscura** con contador (en tema oscuro, ámbar) |

## Dónde vive cada cosa

- **Colores**: `app/lib/core/tema/colores.dart`. Una sola clase `Paleta` con
  dos instancias, `clara` (la del diseño) y `oscura`. Ningún widget escribe
  un color a mano: todo sale de `context.paleta`.
- **Tipografía, radios, espaciado y temas de Material**:
  `app/lib/core/tema/tema.dart`. `Esp` (espaciado), `Curva` (radios),
  `TemaApp.titulo` (Work Sans) y el `TextTheme` completo.
- **Componentes**: `app/lib/ui/componentes.dart`. `Tarjeta`, `Pastilla`
  (chip de estado con punto), `ChipSeleccion` (pestaña con contador),
  `Buscador`, `CabeceraPantalla`, `EstadoVacio`, `FilaDato`,
  `TarjetaMetrica`, `MontoDual`.
- **Formularios**: `app/lib/ui/formulario.dart`. Etiqueta siempre arriba del
  campo, nunca flotante ni solo como placeholder.
- **Navegación**: `app/lib/ui/shell/`. En celular, la barra inferior oscura
  flotante con el "+" de cargar en el medio y "Más" al final; en escritorio,
  la barra lateral.

## Las reglas que no se negocian

1. **Nada por debajo de 13 px, y los datos que importan en 16 o más.** Los
   usuarios de una agencia miran la pantalla ocho horas, y muchos ya usan
   anteojos. El objetivo del diseño es 14 como piso; hoy quedan algunos
   encabezados de tabla en 13, que es lo que entra en el ancho de columna.
2. **El ámbar `#FFC53D` es relleno, nunca tinta.** Ámbar sobre blanco no se
   lee. Para texto o iconos sobre superficie clara se usa `acentoTexto`.
3. **Cada estado se dice de tres formas**: color de fondo, texto y punto
   sólido. Quien no distingue rojo de verde igual lee la etiqueta.
4. **La profundidad se hace con bordes, no con sombras difusas.** Un borde
   se ve en cualquier monitor; una sombra suave, no.
5. **Toque cómodo**: 52 px de alto en botones y campos, 48 en chips, y aire
   entre controles para no errarle al de al lado.

## La barra inferior

Es la que ya tenía la app —al cliente le gustaba— con el agregado del
diseño: pastilla oscura flotante con cinco lugares.

    Panel · Inventario · [ + Cargar ] · Clientes · Más

- **"+" (Cargar)**: abre una hoja con todo lo que se da de alta a mano
  (vehículo, gasto, precio, venta), en el orden en que pasa en la agencia.
  No marca sección activa: es una acción, no un destino.
- **"Más"**: el resto de las secciones y el **cambio de tema** (claro /
  oscuro), que se queda donde estaba.

## Qué pantalla es cada archivo

| Pantalla del diseño | En el código |
|---|---|
| Inicio | `funciones/panel/pantalla_panel.dart` |
| Inventario | `funciones/inventario/pantalla_inventario.dart` |
| Ficha del auto | `funciones/inventario/pantalla_ficha.dart` |
| Clientes | `funciones/interesados/pantalla_interesados.dart` |
| Estadísticas | `funciones/estadisticas/pantalla_estadisticas.dart` |
| Simulador de financiamiento | `funciones/simulador/pantalla_simulador.dart` |
| Más opciones | la hoja de `ui/shell/shell_adaptativo.dart` |

El "Más" del diseño es una pantalla entera; en la app quedó como hoja que
sube desde la barra inferior, porque es lo que el cliente pidió mantener.
Tiene lo mismo: las secciones, el modo oscuro, el tamaño de letra y el
cierre de sesión.

## Cómo mirar una pantalla sin compilar la app

`app/test/capturas_diseno_test.dart` dibuja pantallas con las fuentes reales
y las guarda como PNG:

```
flutter test --update-goldens test/capturas_diseno_test.dart
```

Las imágenes quedan en `app/test/capturas/`. No son pruebas de regresión
(cada sistema operativo dibuja distinto): son para mirar.
