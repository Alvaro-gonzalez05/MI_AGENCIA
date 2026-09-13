// Arma supabase/migraciones_completas.sql concatenando las migraciones.
//
// Ese archivo existe para poder instalar la base de una sola pegada en el
// SQL Editor de Supabase, sin CLI ni Docker. Tenerlo a mano ahorra la mitad
// de una puesta en marcha, pero mantenerlo a mano se olvida: la primera vez
// que alguien agrega una migracion y no la copia, el instalador de un
// archivo queda instalando una base vieja sin que nadie se entere.
//
//     node generar_sql_completo.mjs
//     node generar_sql_completo.mjs --verificar   (falla si quedo desfasado)
//
// El modo --verificar es el que corre en CI.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const DIR = fileURLToPath(new URL('../supabase/migrations/', import.meta.url));
const SALIDA = fileURLToPath(
  new URL('../supabase/migraciones_completas.sql', import.meta.url),
);

const archivos = fs
  .readdirSync(DIR)
  .filter((f) => f.endsWith('.sql'))
  .sort();

const cabecera = `-- =====================================================================
-- MI AGENCIA — esquema completo
-- Las migraciones de supabase/migrations/ concatenadas en orden.
-- Generado automaticamente: no editar a mano, editar las migraciones.
--
-- Para usarlo: pegar entero en el SQL Editor de Supabase y ejecutar.
-- Es idempotente, se puede volver a correr sin romper nada.
--
-- Regenerar con: node tests/generar_sql_completo.mjs
-- =====================================================================

`;

const cuerpo = archivos
  .map((archivo) => {
    const sql = fs.readFileSync(path.join(DIR, archivo), 'utf8').trimEnd();
    return `\n-- >>>>>>>>>>>>>>>>>>>>  ${archivo}  <<<<<<<<<<<<<<<<<<<<\n\n${sql}\n`;
  })
  .join('\n');

const contenido = cabecera + cuerpo;

if (process.argv.includes('--verificar')) {
  const actual = fs.existsSync(SALIDA) ? fs.readFileSync(SALIDA, 'utf8') : '';
  if (actual !== contenido) {
    console.error(
      'supabase/migraciones_completas.sql quedo desfasado de las migraciones.\n' +
        'Corre: node tests/generar_sql_completo.mjs',
    );
    process.exit(1);
  }
  console.log(`migraciones_completas.sql al dia (${archivos.length} migraciones).`);
  process.exit(0);
}

fs.writeFileSync(SALIDA, contenido, 'utf8');
console.log(
  `Escrito supabase/migraciones_completas.sql con ${archivos.length} migraciones.`,
);
