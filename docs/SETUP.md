# Puesta en marcha

Dos cosas dependen de vos y bloquean el avance. Están primero.

---

## 1. Conectar el MCP de Supabase a la cuenta nueva

**Esto no lo puedo hacer yo.** El conector de Supabase que tengo enchufado en Claude
está autenticado contra `desarrolloscodeade@gmail.com` — por eso al pedir el proyecto
nuevo me rebotó diciendo que *ese* usuario ya llegó a su límite de 2 proyectos gratis.
Yo no puedo cambiar de cuenta desde acá: el token de acceso vive en la configuración
de la app, no en el repo.

Lo que hay que hacer, desde la cuenta nueva (`alvarogonzalez7070@gmail.com`):

1. Entrá a <https://supabase.com/dashboard/account/tokens> logueado con la cuenta nueva.
2. **Generate new token**, nombre `claude-code-mi-agencia`. Copialo (se muestra una sola vez).
3. En Claude Desktop: **Settings → Connectors → Supabase**, desconectá el actual y
   reconectá pegando el token de la cuenta nueva.
4. Avisame y yo creo el proyecto `mi-agencia` y corro las 10 migraciones de un saque.

> El token es una credencial con acceso total a tus proyectos: **no me lo pegues en el chat.**
> Va en la configuración del conector y nada más.

**Alternativa si preferís no tocar el conector:** creá el proyecto a mano en el dashboard
(nombre `mi-agencia`, región **South America (São Paulo)**, que es la de menor latencia
desde Argentina) y corré vos mismo los archivos de `supabase/migrations/` en orden, desde
el SQL Editor. Copiar y pegar, del `0001` al `0010`. Yo después me conecto por el cliente
de la app y sigo.

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
