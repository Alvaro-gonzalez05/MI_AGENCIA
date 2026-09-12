# Puesta en marcha

Dos cosas dependen de vos y bloquean el avance. Están primero.

---

## 1. MCP de Supabase propio de este proyecto

Sí, se puede tener un MCP por proyecto: es lo que hace el `.mcp.json` de la raíz.
Queda atado a esta carpeta y **no toca el conector global** de Claude, que sigue
apuntando a `desarrolloscodeade@gmail.com` para tus otros proyectos.

El token no va en el archivo (el `.mcp.json` sí se commitea): se lee de una variable
de entorno.

1. Logueate en Supabase con la cuenta nueva (`alvarogonzalez7070@gmail.com`) y entrá
   a <https://supabase.com/dashboard/account/tokens>.
2. **Generate new token**, nombre `mi-agencia`. Copialo — se muestra una sola vez.
3. Guardalo como variable de entorno de usuario, en una terminal PowerShell:

   ```powershell
   [Environment]::SetEnvironmentVariable('SUPABASE_TOKEN_MI_AGENCIA', 'TU_TOKEN_ACA', 'User')
   ```

4. Cerrá y volvé a abrir Claude **con esta carpeta (`mi-agencia`) como directorio de
   trabajo**, para que levante el `.mcp.json`. Aprobá el servidor cuando lo pregunte.

> El token da acceso total a tus proyectos de Supabase: **no lo pegues en el chat.**
> Va en la variable de entorno y nada más.

### Alternativa sin MCP

Creá el proyecto a mano en el dashboard (nombre `mi-agencia`, región
**South America (São Paulo)**, la de menor latencia desde Argentina) y pegá los
archivos de `supabase/migrations/` en el SQL Editor **en orden, del `0001` al `0010`**.
Son idempotentes (`if not exists` / `or replace`), así que se pueden volver a correr
sin romper nada.

Las migraciones ya están verificadas: `tests/` las ejecuta contra un Postgres real
y compara el motor de cálculo contra el JavaScript original del cliente.

---

## 2. API key de ArgAutos (valor de revista)

La API anónima corta a **3 requests por minuto**, lo cual alcanza para probar pero no
para producción. Pedí la key gratuita en <https://argautos.com> y guardala como secreto
de Supabase (no en el repo):

```bash
supabase secrets set ARGAUTOS_API_KEY=xxxxx --project-ref <ref-del-proyecto>
```

Con la key, la Edge Function `sync-catalogo` espeja las 69 marcas / 665 modelos /
6.163 versiones en nuestra base una vez por mes. La app nunca le pega a ArgAutos en
vivo: consulta nuestro Postgres, que responde en milisegundos y funciona sin internet.

---

## 3. Herramientas locales (Flutter)

Estado de tu máquina, ya verificado:

| Herramienta | Estado | Nota |
|---|---|---|
| Node 22 + npm 10 | instalado | alcanza para la CLI de Supabase |
| Git 2.41 | instalado | |
| Android SDK | instalado | en `%LOCALAPPDATA%\Android\Sdk` |
| Java | **roto** | apunta a un JRE 1.8 de 32 bits con el `jvm.cfg` corrupto. Android exige **JDK 17** |
| Flutter SDK | falta | |
| Visual Studio + C++ | falta | obligatorio para compilar el .exe de Windows |

### Ojo con el disco

`C:` tiene **18,7 GB libres** y `D:` tiene **264 GB**. El stack de Flutter se come
fácil 15 GB, y por defecto **todo va a `C:`**. Por eso instalamos el SDK en `D:` y
redirigimos las cachés pesadas con variables de entorno:

| Variable | Valor | Qué guarda |
|---|---|---|
| `PUB_CACHE` | `D:\dev\.pub-cache` | paquetes de Dart (~1-2 GB) |
| `GRADLE_USER_HOME` | `D:\dev\.gradle` | dependencias de Android (~5-10 GB) |

El script `scripts/setup-flutter.ps1` deja todo eso configurado.

### Lo único que sí ocupa C:

Visual Studio 2022 Community con la carga **"Desarrollo para el escritorio con C++"**
(~10 GB). Es requisito de Flutter para Windows y no se puede mover fácil de `C:`.
Si el disco aprieta, se puede desarrollar y probar todo en Android + web primero, y
dejar el build de Windows para el final.
