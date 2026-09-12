let DATA;
function d(str){ return new Date(str+"T00:00:00"); }
function todayDate(){ return new Date(); }
function daysBetween(a,b){ return Math.round((b-a)/86400000); }
function fmtARS(n){ return "$"+Math.round(n).toLocaleString("es-AR"); }
function fmtPct(n, dec){ if(n===null||n===undefined||isNaN(n)) return "-"; dec = dec===undefined?1:dec; return (n*100).toFixed(dec)+"%"; }
function seedData(){
  return {
    vehiculos: [
      {id:"V001",marca:"Toyota",modelo:"Corolla",anio:2021,version:"XEI 1.8 CVT",km:62000,fechaCompra:"2026-05-28",fechaIngreso:"2026-05-30",precioCompra:19800000,precioObjetivo:22500000,estado:"En stock",obs:"Único dueño, service oficial"},
      {id:"V002",marca:"Volkswagen",modelo:"Amarok",anio:2020,version:"V6 Highline",km:98000,fechaCompra:"2026-03-10",fechaIngreso:"2026-03-12",precioCompra:34500000,precioObjetivo:39900000,estado:"En stock",obs:"Requiere cubiertas nuevas"},
      {id:"V003",marca:"Ford",modelo:"Ranger",anio:2022,version:"XLT 3.2 4x4",km:71000,fechaCompra:"2026-07-14",fechaIngreso:"2026-07-16",precioCompra:41000000,precioObjetivo:46500000,estado:"En stock",obs:"Ingresó por parte de pago"},
      {id:"V004",marca:"Chevrolet",modelo:"Cruze",anio:2019,version:"LTZ 1.4T",km:88000,fechaCompra:"2026-02-05",fechaIngreso:"2026-02-08",precioCompra:15200000,precioObjetivo:18500000,estado:"En stock",obs:"Detalle de chapa en puerta trasera"},
      {id:"V005",marca:"Fiat",modelo:"Cronos",anio:2023,version:"Drive 1.3 GSE",km:34000,fechaCompra:"2026-08-01",fechaIngreso:"2026-08-03",precioCompra:16900000,precioObjetivo:19200000,estado:"En stock",obs:"Muy bajo kilometraje"},
      {id:"V006",marca:"Peugeot",modelo:"208",anio:2022,version:"Allure 1.6",km:41000,fechaCompra:"2026-06-18",fechaIngreso:"2026-06-20",precioCompra:17400000,precioObjetivo:20000000,estado:"En stock",obs:""},
      {id:"V007",marca:"Renault",modelo:"Duster",anio:2021,version:"Iconic 1.3T",km:66000,fechaCompra:"2026-04-22",fechaIngreso:"2026-04-25",precioCompra:21000000,precioObjetivo:24500000,estado:"En preparación",obs:"En taller por chapa y pintura"},
      {id:"V008",marca:"Honda",modelo:"HR-V",anio:2020,version:"EXL CVT",km:79000,fechaCompra:"2026-01-15",fechaIngreso:"2026-01-18",precioCompra:24800000,precioObjetivo:29000000,estado:"En stock",obs:"Difícil rotación, revisar precio"},
      {id:"V009",marca:"Toyota",modelo:"Hilux",anio:2019,version:"SRV 4x4 AT",km:132000,fechaCompra:"2026-05-05",fechaIngreso:"2026-05-07",precioCompra:32000000,precioObjetivo:37500000,estado:"Reservado",obs:"Seña recibida"},
      {id:"V010",marca:"Nissan",modelo:"Kicks",anio:2021,version:"Advance CVT",km:58000,fechaCompra:"2026-07-28",fechaIngreso:"2026-07-30",precioCompra:20500000,precioObjetivo:23500000,estado:"En stock",obs:""},
      {id:"V011",marca:"Volkswagen",modelo:"Gol Trend",anio:2018,version:"Trendline 1.6",km:105000,fechaCompra:"2026-02-20",fechaIngreso:"2026-02-22",precioCompra:9800000,precioObjetivo:12500000,estado:"En stock",obs:"Unidad de entrada, alta demanda"},
      {id:"V012",marca:"Chevrolet",modelo:"Tracker",anio:2022,version:"Premier 1.2T",km:45000,fechaCompra:"2026-06-02",fechaIngreso:"2026-06-04",precioCompra:26500000,precioObjetivo:30500000,estado:"En stock",obs:""},
      {id:"V013",marca:"Ford",modelo:"EcoSport",anio:2019,version:"SE 1.5",km:92000,fechaCompra:"2026-03-01",fechaIngreso:"2026-03-04",precioCompra:13500000,precioObjetivo:16500000,estado:"En stock",obs:"Vendida a cliente recurrente",foto:null},
    ],
    gastos: [
      {id:"G001",idVehiculo:"V001",fecha:"2026-06-02",categoria:"Service",desc:"Service completo 60.000 km",importe:320000},
      {id:"G002",idVehiculo:"V001",fecha:"2026-06-05",categoria:"Lavado/Detallado",desc:"Detallado interior y pulido",importe:85000},
      {id:"G003",idVehiculo:"V001",fecha:"2026-06-10",categoria:"Transferencia",desc:"Gastos de transferencia",importe:210000},
      {id:"G004",idVehiculo:"V002",fecha:"2026-03-20",categoria:"Cubiertas",desc:"4 cubiertas 255/60 R18",importe:1450000},
      {id:"G005",idVehiculo:"V002",fecha:"2026-04-02",categoria:"Service",desc:"Service mayor V6",importe:480000},
      {id:"G006",idVehiculo:"V002",fecha:"2026-05-15",categoria:"Reparaciones",desc:"Reparación tren delantero",importe:620000},
      {id:"G007",idVehiculo:"V002",fecha:"2026-06-20",categoria:"Almacenamiento",desc:"Cochera 3 meses",importe:180000},
      {id:"G008",idVehiculo:"V003",fecha:"2026-07-20",categoria:"Lavado/Detallado",desc:"Lavado y detallado",importe:70000},
      {id:"G009",idVehiculo:"V003",fecha:"2026-07-25",categoria:"Gestoría",desc:"Gestoría documentación",importe:150000},
      {id:"G010",idVehiculo:"V004",fecha:"2026-02-15",categoria:"Chapa y pintura",desc:"Chapa y pintura puerta trasera",importe:540000},
      {id:"G011",idVehiculo:"V004",fecha:"2026-03-10",categoria:"Service",desc:"Service de mantenimiento",importe:240000},
      {id:"G012",idVehiculo:"V004",fecha:"2026-05-05",categoria:"Almacenamiento",desc:"Cochera 3 meses",importe:180000},
      {id:"G013",idVehiculo:"V004",fecha:"2026-07-01",categoria:"Reparaciones",desc:"Cambio de embrague",importe:710000},
      {id:"G014",idVehiculo:"V005",fecha:"2026-08-05",categoria:"Lavado/Detallado",desc:"Lavado de entrega",importe:45000},
      {id:"G015",idVehiculo:"V006",fecha:"2026-06-25",categoria:"Service",desc:"Service 40.000 km",importe:260000},
      {id:"G016",idVehiculo:"V006",fecha:"2026-07-08",categoria:"Cubiertas",desc:"2 cubiertas delanteras",importe:380000},
      {id:"G017",idVehiculo:"V007",fecha:"2026-05-02",categoria:"Chapa y pintura",desc:"Reparación lateral completo",importe:980000},
      {id:"G018",idVehiculo:"V007",fecha:"2026-05-20",categoria:"Service",desc:"Service + correa",importe:410000},
      {id:"G019",idVehiculo:"V007",fecha:"2026-06-15",categoria:"Reparaciones",desc:"Suspensión trasera",importe:350000},
      {id:"G020",idVehiculo:"V008",fecha:"2026-01-25",categoria:"Service",desc:"Service CVT",importe:390000},
      {id:"G021",idVehiculo:"V008",fecha:"2026-02-18",categoria:"Cubiertas",desc:"4 cubiertas 215/55 R17",importe:1120000},
      {id:"G022",idVehiculo:"V008",fecha:"2026-04-10",categoria:"Almacenamiento",desc:"Cochera 3 meses",importe:180000},
      {id:"G023",idVehiculo:"V008",fecha:"2026-06-05",categoria:"Reparaciones",desc:"Aire acondicionado",importe:290000},
      {id:"G024",idVehiculo:"V008",fecha:"2026-07-12",categoria:"Almacenamiento",desc:"Cochera 2 meses",importe:120000},
      {id:"G025",idVehiculo:"V009",fecha:"2026-05-15",categoria:"Service",desc:"Service 130.000 km",importe:520000},
      {id:"G026",idVehiculo:"V009",fecha:"2026-05-28",categoria:"Patentamiento",desc:"Trámite patentamiento",importe:340000},
      {id:"G027",idVehiculo:"V010",fecha:"2026-08-02",categoria:"Lavado/Detallado",desc:"Detallado completo",importe:90000},
      {id:"G028",idVehiculo:"V010",fecha:"2026-08-08",categoria:"Transferencia",desc:"Gastos de transferencia",importe:230000},
      {id:"G029",idVehiculo:"V011",fecha:"2026-03-01",categoria:"Reparaciones",desc:"Motor de arranque",importe:180000},
      {id:"G030",idVehiculo:"V011",fecha:"2026-03-15",categoria:"Chapa y pintura",desc:"Retoque de pintura general",importe:420000},
      {id:"G031",idVehiculo:"V011",fecha:"2026-06-01",categoria:"Almacenamiento",desc:"Cochera 4 meses",importe:240000},
      {id:"G032",idVehiculo:"V012",fecha:"2026-06-10",categoria:"Service",desc:"Service completo",importe:300000},
      {id:"G033",idVehiculo:"V012",fecha:"2026-06-18",categoria:"Lavado/Detallado",desc:"Detallado de entrega",importe:80000},
      {id:"G034",idVehiculo:"V013",fecha:"2026-03-12",categoria:"Reparaciones",desc:"Caja de dirección",importe:450000},
      {id:"G035",idVehiculo:"V013",fecha:"2026-03-25",categoria:"Service",desc:"Service general",importe:230000},
      {id:"G036",idVehiculo:"V013",fecha:"2026-04-05",categoria:"Transferencia",desc:"Gastos de transferencia",importe:190000},
    ],
    precios: [
      {id:"P001",idVehiculo:"V001",fecha:"2026-08-10",nuevoPrecio:22100000,motivo:"Ajuste por baja de consultas"},
      {id:"P002",idVehiculo:"V002",fecha:"2026-06-05",nuevoPrecio:38500000,motivo:"Reducción para acelerar rotación"},
      {id:"P003",idVehiculo:"V004",fecha:"2026-05-10",nuevoPrecio:17800000,motivo:"Ajuste de mercado"},
      {id:"P004",idVehiculo:"V004",fecha:"2026-07-15",nuevoPrecio:17200000,motivo:"Sigue sin venderse"},
      {id:"P005",idVehiculo:"V007",fecha:"2026-06-20",nuevoPrecio:25200000,motivo:"Suba por reparaciones realizadas"},
      {id:"P006",idVehiculo:"V008",fecha:"2026-04-05",nuevoPrecio:27500000,motivo:"Baja rotación"},
      {id:"P007",idVehiculo:"V008",fecha:"2026-06-20",nuevoPrecio:26200000,motivo:"Segunda baja de precio"},
      {id:"P008",idVehiculo:"V009",fecha:"2026-07-01",nuevoPrecio:36800000,motivo:"Negociación con cliente"},
      {id:"P009",idVehiculo:"V011",fecha:"2026-05-01",nuevoPrecio:12900000,motivo:"Alta demanda del segmento"},
      {id:"P010",idVehiculo:"V012",fecha:"2026-07-05",nuevoPrecio:29800000,motivo:"Cierre de operación"},
      {id:"P011",idVehiculo:"V013",fecha:"2026-05-10",nuevoPrecio:15900000,motivo:"Ajuste para cerrar venta"},
    ],
    ventas: [
      {id:"VT001",idVehiculo:"V012",fechaVenta:"2026-07-18",precioFinal:29500000,gastosFinales:120000,cliente:"M. Fernández",vendedor:"Laura G.",obs:"Financiación propia 12 cuotas"},
      {id:"VT002",idVehiculo:"V013",fechaVenta:"2026-05-22",precioFinal:15700000,gastosFinales:90000,cliente:"J. Sosa",vendedor:"Diego R.",obs:"Cliente recurrente"},
    ],
    interesados: [
      {id:"I001",idVehiculo:"V003",nombre:"L. Benítez",telefono:"11-4455-2200",fecha:"2026-08-10",obs:"Preguntó por financiación a 12 cuotas"},
      {id:"I002",idVehiculo:"V008",nombre:"R. Ibarra",telefono:"11-6677-8899",fecha:"2026-08-14",obs:"Va a volver con su pareja a ver la unidad"},
      {id:"I003",idVehiculo:"V012",nombre:"C. Domínguez",telefono:"11-2233-4455",fecha:"2026-08-18",obs:"Pidió que le avisen si baja el precio"},
    ],
    // VALOR DE REVISTA — tabla propia, cargada a mano con datos reales (no inventados) tomados de
    // la Guía de Precios de Autocosmos Argentina, que a su vez cita a la Cámara del Comercio Automotor
    // (CCA) como fuente oficial — el mismo tipo de fuente que usa InfoAuto. No se conecta en vivo a
    // ningún sitio externo (el Artifact no puede hacer llamadas de red a sitios no permitidos, y ni
    // InfoAuto ni InfoUsados ofrecen consulta gratis/programática), así que hay que actualizarla a mano
    // periódicamente. Cargada el 28/08/2026.
    referencias: [
      {marca:"Toyota", modelo:"Corolla", anio:2021, precio:29500000, fuente:"Autocosmos/CCA — HV 1.8 XEI CVT", url:"https://www.autocosmos.com.ar/guiadeprecios/toyota/corolla/2021"},
      {marca:"Volkswagen", modelo:"Amarok", anio:2020, precio:47200000, fuente:"Autocosmos/CCA — V6 4x4 8AT Highline", url:"https://www.autocosmos.com.ar/guiadeprecios/volkswagen/amarok-pick---up/2020"},
      {marca:"Ford", modelo:"Ranger", anio:2022, precio:38300000, fuente:"Autocosmos/CCA — D/C 3.2 XLT 4x4 6AT", url:"https://www.autocosmos.com.ar/guiadeprecios/ford/ranger-pick---up/2022"},
      {marca:"Chevrolet", modelo:"Cruze", anio:2019, precio:23100000, fuente:"Autocosmos/CCA — 4P LTZ AT", url:"https://www.autocosmos.com.ar/guiadeprecios/chevrolet/cruze/2019"},
      {marca:"Fiat", modelo:"Cronos", anio:2023, precio:20000000, fuente:"Autocosmos/CCA — Drive GSE", url:"https://www.autocosmos.com.ar/guiadeprecios/fiat/cronos/2023"},
      {marca:"Peugeot", modelo:"208", anio:2022, precio:20650000, fuente:"Autocosmos/CCA — Allure 1.6", url:"https://www.autocosmos.com.ar/guiadeprecios/peugeot/208/2022"},
      {marca:"Renault", modelo:"Duster", anio:2021, precio:25500000, fuente:"Autocosmos/CCA — Iconic 1.3T 4x4", url:"https://www.autocosmos.com.ar/guiadeprecios/renault/duster/2021"},
      {marca:"Honda", modelo:"HR-V", anio:2020, precio:36100000, fuente:"Autocosmos/CCA — EX-L 2WD CVT", url:"https://www.autocosmos.com.ar/guiadeprecios/honda/hr-v/2020"},
      {marca:"Toyota", modelo:"Hilux", anio:2019, precio:36400000, fuente:"Autocosmos/CCA — D/C 2.8 SRV 4x4 6AT", url:"https://www.autocosmos.com.ar/guiadeprecios/toyota/hilux-pick---up/2019"},
      {marca:"Nissan", modelo:"Kicks", anio:2021, precio:24150000, fuente:"Autocosmos/CCA — Advance CVT", url:"https://www.autocosmos.com.ar/guiadeprecios/nissan/kicks/2021"},
      {marca:"Volkswagen", modelo:"Gol Trend", anio:2018, precio:13900000, fuente:"Autocosmos/CCA — 5P Trendline", url:"https://www.autocosmos.com.ar/guiadeprecios/volkswagen/gol-trend/2018"},
      {marca:"Chevrolet", modelo:"Tracker", anio:2022, precio:27450000, fuente:"Autocosmos/CCA — 5P 1.2T 6AT Premier", url:"https://www.autocosmos.com.ar/guiadeprecios/chevrolet/tracker/2022"},
      {marca:"Ford", modelo:"EcoSport", anio:2019, precio:20500000, fuente:"Estimado sobre avisos reales (deruedas.com.ar), SE 1.5, rango $18,3M–$23,9M", url:"https://www.deruedas.com.ar/precio/Autos/ford/EcoSport/2019"},
    ],
    config: {
      diasVerde:30, diasAmarillo:60, diasRojo:90,
      margenMinimo:0.10, margenObjetivo:0.30,
      toleranciaCaidaMargen:0.005, umbralGastosAltos:1000000,
      toleranciaDesvioPrecio:0.02, redondeo:50000, capacidad:60,
      tasaFinanciacionMensual:0.06,
      tipoCambio:1515, tipoCambioOficial:1515, tipoCambioMayorista:1499, tipoCambioBlue:1550,
      fechaCotizacion:"2026-08-21",
      ipcSerie: [
        {mes:"2025-07", variacion:null, fuente:null, url:null},
        {mes:"2025-08", variacion:0.019, fuente:"INDEC, Informe técnico IPC julio 2026 — serie de variaciones mensuales del nivel general, total nacional.", url:"https://www.indec.gob.ar/uploads/informesdeprensa/ipc_08_2642C82F62AE.pdf"},
        {mes:"2025-09", variacion:0.021, fuente:"INDEC, Informe técnico IPC julio 2026.", url:"https://www.indec.gob.ar/uploads/informesdeprensa/ipc_08_2642C82F62AE.pdf"},
        {mes:"2025-10", variacion:0.023, fuente:"INDEC, Informe técnico IPC julio 2026.", url:"https://www.indec.gob.ar/uploads/informesdeprensa/ipc_08_2642C82F62AE.pdf"},
        {mes:"2025-11", variacion:0.025, fuente:"INDEC, Informe técnico IPC julio 2026.", url:"https://www.indec.gob.ar/uploads/informesdeprensa/ipc_08_2642C82F62AE.pdf"},
        {mes:"2025-12", variacion:0.028, fuente:"INDEC, Informe técnico IPC julio 2026.", url:"https://www.indec.gob.ar/uploads/informesdeprensa/ipc_08_2642C82F62AE.pdf"},
        {mes:"2026-01", variacion:0.029, fuente:"INDEC, Informe técnico IPC enero 2026 — nivel general 2,9% mensual.", url:"https://www.indec.gob.ar/uploads/informesdeprensa/ipc_02_261443D4406C.pdf"},
        {mes:"2026-02", variacion:0.029, fuente:"INDEC, Informe técnico IPC julio 2026.", url:"https://www.indec.gob.ar/uploads/informesdeprensa/ipc_08_2642C82F62AE.pdf"},
        {mes:"2026-03", variacion:0.034, fuente:"INDEC, Informe técnico IPC marzo 2026 — nivel general 3,4% mensual.", url:"https://www.indec.gob.ar/uploads/informesdeprensa/ipc_04_26853171E136.pdf"},
        {mes:"2026-04", variacion:0.026, fuente:"INDEC, Informe técnico IPC abril 2026 — nivel general 2,6% mensual.", url:"https://www.indec.gob.ar/uploads/informesdeprensa/ipc_05_2680B692D2F5.pdf"},
        {mes:"2026-05", variacion:0.021, fuente:"INDEC, Informe técnico IPC mayo 2026 — nivel general 2,1% mensual.", url:"https://www.indec.gob.ar/uploads/informesdeprensa/ipc_06_26C132AEE4E9.pdf"},
        {mes:"2026-06", variacion:0.019, fuente:"INDEC, Informe técnico IPC julio 2026.", url:"https://www.indec.gob.ar/uploads/informesdeprensa/ipc_08_2642C82F62AE.pdf"},
        {mes:"2026-07", variacion:0.021, fuente:"INDEC, Informe técnico IPC julio 2026 — nivel general 2,1% mensual.", url:"https://www.indec.gob.ar/uploads/informesdeprensa/ipc_08_2642C82F62AE.pdf"},
        {mes:"2026-08", variacion:0.021, fuente:"Proyección: el INDEC publica agosto a mediados de septiembre. Por defecto se usa la variación de julio (2,1%). Reemplazala por el dato real cuando salga.", url:null, proyeccion:true},
      ],
    },
  };
}
function ipcIndices(){
  let acc = 100;
  return DATA.config.ipcSerie.map((row,i)=>{
    if(i>0) acc = acc*(1+row.variacion);
    return {...row, indice:acc};
  });
}
function mesDeHoy(){
  const h = todayDate();
  return h.getFullYear()+"-"+String(h.getMonth()+1).padStart(2,"0");
}
function indiceHoy(){
  const series = ipcIndices();
  const found = series.find(r=>r.mes===mesDeHoy());
  return found ? found.indice : series[series.length-1].indice;
}
function ipcIndiceEnMes(fechaStr){
  const series = ipcIndices();
  const found = series.find(r=>r.mes===fechaStr.slice(0,7));
  return found ? found.indice : indiceHoy();
}
function importeGastoHoy(g){
  return g.importe * indiceHoy() / ipcIndiceEnMes(g.fecha);
}
function computeInventory(){
  const cfg = DATA.config;
  const hoy = todayDate();
  return DATA.vehiculos.map(v=>{
    const venta = DATA.ventas.find(x=>x.idVehiculo===v.id) || null;
    const estado = venta ? "Vendido" : v.estado;
    const gastosVehiculo = DATA.gastos.filter(g=>g.idVehiculo===v.id);
    const gastosAcum = gastosVehiculo.reduce((s,g)=>s+g.importe,0) + (venta? venta.gastosFinales : 0);
    const costoTotal = v.precioCompra + gastosAcum;
    const fechaFin = venta ? d(venta.fechaVenta) : hoy;
    const diasEnStock = daysBetween(d(v.fechaIngreso), fechaFin);

    const historial = DATA.precios.filter(p=>p.idVehiculo===v.id).sort((a,b)=>d(a.fecha)-d(b.fecha));
    const precioActual = historial.length ? historial[historial.length-1].nuevoPrecio : v.precioObjetivo;

    const capitalInmovilizado = estado==="Vendido" ? 0 : costoTotal;
    const gananciaEstimada = precioActual - costoTotal;
    const margenEsperado = v.precioObjetivo ? (v.precioObjetivo - costoTotal)/v.precioObjetivo : 0;
    const margenActual = precioActual ? (precioActual - costoTotal)/precioActual : 0;
    const margenReal = venta ? (venta.precioFinal - costoTotal)/venta.precioFinal : null;

    const precioParaMargenObjetivo = costoTotal/(1-cfg.margenObjetivo);
    const ajusteNecesario = precioActual ? (precioParaMargenObjetivo/precioActual - 1) : 0;
    const varVsObjetivo = v.precioObjetivo ? (precioActual/v.precioObjetivo - 1) : null;
    const gastosRatio = v.precioCompra ? gastosAcum/v.precioCompra : 0;
    const costoDiario = diasEnStock>0 ? costoTotal/diasEnStock : costoTotal;
    const cantidadGastos = gastosVehiculo.length;
    const precioParaMargenMinimo = costoTotal/(1-cfg.margenMinimo);
    const precioEquilibrio = costoTotal;

    // Ajuste por inflación (IPC INDEC) — replica Inventario!Z:AD
    const idxHoy = indiceHoy();
    const indiceCompra = ipcIndiceEnMes(v.fechaIngreso);
    const costoTotalHoy = v.precioCompra*idxHoy/indiceCompra + gastosVehiculo.reduce((s,g)=>s+importeGastoHoy(g),0) + (venta? venta.gastosFinales : 0);
    const margenRealIPC = precioActual ? (precioActual - costoTotalHoy)/precioActual : null;
    const gananciaRealIPC = precioActual - costoTotalHoy;
    const gananciaRealIPCUSD = gananciaRealIPC/cfg.tipoCambio;

    let alerta;
    if(estado==="Vendido") alerta="vendido";
    else if(diasEnStock>=cfg.diasRojo) alerta="critico";
    else if(diasEnStock>=cfg.diasAmarillo) alerta="atencion";
    else if(diasEnStock>=cfg.diasVerde) alerta="observar";
    else alerta="normal";

    const diagParts = [];
    if(estado==="Vendido"){
      diagParts.push("✅ Vendido en "+diasEnStock+" días con margen real de "+fmtPct(margenReal)+".");
    }else{
      if(diasEnStock>=cfg.diasRojo) diagParts.push("🔴 Lleva "+diasEnStock+" días en stock.");
      else if(diasEnStock>=cfg.diasAmarillo) diagParts.push("⚠️ Lleva "+diasEnStock+" días en stock.");
      else if(diasEnStock>=cfg.diasVerde) diagParts.push("🟡 Lleva "+diasEnStock+" días en stock, dentro de lo esperable.");
      else diagParts.push("🟢 Lleva "+diasEnStock+" días en stock, plazo normal.");
      if(margenActual < cfg.margenMinimo) diagParts.push("⚠️ Margen actual "+fmtPct(margenActual)+", por debajo del mínimo.");
      if(margenActual < margenEsperado - cfg.toleranciaCaidaMargen) diagParts.push("📉 El margen cayó de "+fmtPct(margenEsperado)+" a "+fmtPct(margenActual)+".");
      if(gastosAcum >= cfg.umbralGastosAltos) diagParts.push("💰 "+fmtARS(gastosAcum)+" de gastos acumulados.");
      if(margenActual >= cfg.margenObjetivo) diagParts.push("📈 Margen por encima del objetivo.");
      if(ajusteNecesario > cfg.toleranciaDesvioPrecio) diagParts.push("🎯 Para el margen objetivo habría que publicarlo a "+fmtARS(precioParaMargenObjetivo)+".");
    }

    return {
      ...v, estado, venta, gastosAcum, costoTotal, diasEnStock, precioActual,
      capitalInmovilizado, gananciaEstimada, margenEsperado, margenActual, margenReal,
      precioParaMargenObjetivo, ajusteNecesario, alerta, diagnostico: diagParts.join(" "),
      historial, varVsObjetivo, gastosRatio, costoDiario, cantidadGastos,
      precioParaMargenMinimo, precioEquilibrio, gastosVehiculo,
      indiceCompra, costoTotalHoy, margenRealIPC, gananciaRealIPC, gananciaRealIPCUSD,
    };
  });
}

export const DATA_SEED = (DATA = seedData());
export { computeInventory };
