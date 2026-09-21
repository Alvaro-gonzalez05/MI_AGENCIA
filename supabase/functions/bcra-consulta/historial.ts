// =====================================================================
//  Lectura del historial de 24 meses de la Central de Deudores.
//
//  Va en un archivo aparte, sin imports, a propósito: es lógica pura, y así
//  se puede probar con Node contra respuestas reales del BCRA
//  (tests/historial_bcra.mjs) sin levantar la Edge Function ni Supabase.
//
//  Por qué existe: /Deudas/{cuit} devuelve SOLO el último período. Alguien
//  que fue irrecuperable hace un año y medio y ya pagó contesta 404 ahí, y
//  la app lo mostraba como "sin deudas". El historial está en
//  /Deudas/Historicas/{cuit}, y es lo que muestra la web oficial del BCRA.
// =====================================================================

export interface EntidadMes {
  entidad: string;
  /** 0 = la entidad aparece ese mes pero sin deuda. */
  situacion: number;
  /** En MILES de pesos, como lo informa el BCRA. */
  monto: number;
  procesoJud: boolean;
  enRevision: boolean;
}

export interface MesHistorico {
  /** "202607" */
  periodo: string;
  /** Peor situación del mes entre todas las entidades. 0 = sin deuda. */
  situacion: number;
  /**
   * Lo que informó cada entidad ese mes: el detalle por entidad y por mes
   * que pidió el cliente para el informe (checklist tanda 2, punto 2.4).
   * Lo peor primero.
   */
  entidades: EntidadMes[];
}

export interface ResumenHistorial {
  /** Del más nuevo al más viejo, un renglón por mes informado. */
  historico: MesHistorico[];
  /** Peor situación (1-6) en los 12 meses más recientes, o null. */
  situacionMax12m: number | null;
  /** Peor situación (1-6) en los 24 meses, o null. */
  situacionMax24m: number | null;
  /** Último mes con situación 2 o peor, o null si nunca la tuvo. */
  ultimoPeriodoIrregular: string | null;
  /** Razón social, que a veces viene solo en el histórico. */
  denominacion: string | null;
}

/** Meses entre dos períodos "AAAAMM": mesesEntre("202607","202508") = 11. */
export function mesesEntre(masNuevo: string, masViejo: string): number {
  const a = Number(masNuevo.slice(0, 4)) * 12 + Number(masNuevo.slice(4, 6));
  const b = Number(masViejo.slice(0, 4)) * 12 + Number(masViejo.slice(4, 6));
  return a - b;
}

/**
 * Resume la respuesta de /Deudas/Historicas.
 *
 * `payload` es el JSON tal como lo devuelve el BCRA, o null si contestó 404
 * (no tiene nada en 24 meses).
 *
 * Detalles que no son obvios y que salieron de mirar respuestas reales:
 *
 * - En el histórico la situación puede venir en 0. No es una categoría del
 *   BCRA (van del 1 al 6): es un mes en que la entidad sigue apareciendo
 *   pero sin deuda. Cuenta como "sin deuda", no como "situación buena".
 * - Las ventanas de 12 y 24 meses se cuentan desde el período más nuevo que
 *   trajo el BCRA, no desde hoy. El BCRA publica con unos dos meses de
 *   atraso; contar desde hoy achicaría la ventana en silencio.
 */
export function resumirHistorial(payload: unknown): ResumenHistorial {
  const vacio: ResumenHistorial = {
    historico: [],
    situacionMax12m: null,
    situacionMax24m: null,
    ultimoPeriodoIrregular: null,
    denominacion: null,
  };
  if (!payload || typeof payload !== 'object') return vacio;

  const resultados = ((payload as Record<string, unknown>).results ?? {}) as Record<
    string,
    unknown
  >;
  const periodos = (resultados.periodos ?? []) as Array<Record<string, unknown>>;

  const historico: MesHistorico[] = periodos
    .filter((p) => typeof p.periodo === 'string' && /^\d{6}$/.test(p.periodo as string))
    .map((p) => {
      const crudas = (p.entidades ?? []) as Array<Record<string, unknown>>;
      const entidades: EntidadMes[] = crudas
        .map((e) => {
          const s = Number(e.situacion ?? 0);
          const m = Number(e.monto ?? 0);
          return {
            entidad: String(e.entidad ?? 'Sin identificar').trim(),
            situacion: Number.isFinite(s) ? s : 0,
            monto: Number.isFinite(m) ? m : 0,
            procesoJud: e.procesoJud === true,
            enRevision: e.enRevision === true,
          };
        })
        .sort((a, b) => b.situacion - a.situacion || b.monto - a.monto);
      const peor = entidades.reduce((max, e) => Math.max(max, e.situacion), 0);
      return { periodo: p.periodo as string, situacion: peor, entidades };
    })
    // No se confía en el orden en que llegan: se ordena del más nuevo al más
    // viejo, que es como se leen y como se dibujan.
    .sort((a, b) => b.periodo.localeCompare(a.periodo));

  if (historico.length === 0) {
    return { ...vacio, denominacion: (resultados.denominacion as string) ?? null };
  }

  const masNuevo = historico[0].periodo;
  const peorEn = (meses: number) => {
    const peor = historico
      .filter((m) => mesesEntre(masNuevo, m.periodo) < meses)
      .reduce((max, m) => Math.max(max, m.situacion), 0);
    return peor > 0 ? peor : null;
  };

  return {
    historico,
    situacionMax12m: peorEn(12),
    situacionMax24m: peorEn(24),
    ultimoPeriodoIrregular: historico.find((m) => m.situacion >= 2)?.periodo ?? null,
    denominacion: (resultados.denominacion as string) ?? null,
  };
}
