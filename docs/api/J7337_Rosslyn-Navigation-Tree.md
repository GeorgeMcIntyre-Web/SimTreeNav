# Navigation Tree for J7337_Rosslyn (DESIGN1 Schema)

**Project ID:** 60  
**Project Name:** J7337_Rosslyn  
**External ID:** PP-DESIGN2-24-3-2016-16-15-7-0-60

## Tree Structure

```
J7337_Rosslyn (60)
│
├── Löschen (615)
│   ├── Admin (617)
│   ├── J7337_Rosslyn (60) [circular reference]
│   ├── Ruaan (616)
│   └── User_2_EINCHECKEN!! (502)
│
├── Produkt- und Prozessplanung (611)
│   ├── Bibliotheken (618)
│   ├── COC AF (612)
│   ├── COC BG (613)
│   ├── COC KG (610)
│   ├── COC Paint (307119)
│   ├── COC_Bolzen (501)
│   ├── J7337_Rosslyn (60) [circular reference]
│   ├── Produkt Importe (625)
│   ├── SEP_Export (494)
│   ├── SEP_Import (493)
│   └── Working folder (232265)
│
├── Projekt MA (614)
│   ├── ADMIN (619)
│   ├── J7337_Rosslyn (60) [circular reference]
│   └── Methoden (620)
│
├── Pruefplanung (512)
│   ├── COC AF (513)
│   ├── COC BG (514)
│   ├── COC KG (515)
│   └── J7337_Rosslyn (60) [circular reference]
│
├── Standardstruktur Logistik (634)
│   ├── J7337_Rosslyn (60) [circular reference]
│   └── Logistikbibliotheken (607)
│
└── Variantenbibliothek (550)
    ├── J7337_Rosslyn (60) [circular reference]
    └── Variantenfilter (609)
```

## Level 1 Children (Direct Children)

| OBJECT_ID | Name | External ID | Children Count | Status |
|-----------|------|-------------|---------------|--------|
| 615 | Löschen | PP-pptrb_02-26-2-2007-13-16-25-20-1872879 | 3 | Open |
| 611 | Produkt- und Prozessplanung | PP-pptrb_02-26-2-2007-12-52-32-20-1872842 | 10 | Open |
| 614 | Projekt MA | PP-pptrb_02-26-2-2007-13-16-25-20-1872877 | 2 | Open |
| 512 | Pruefplanung | PP-PPRB1-2-4-2012-11-40-43-63175917-63176312 | 3 | Open |
| 634 | Standardstruktur Logistik | Standardstruktur_Logistik_TK | 2 | Open |
| 550 | Variantenbibliothek | PP-PPTRB-26-5-2003-14-12-33-2884180-2884199 | 1 | Open |

## Level 2 Children (Grandchildren)

### Under "Löschen" (615)
- Admin (617)
- Ruaan (616)
- User_2_EINCHECKEN!! (502)

### Under "Produkt- und Prozessplanung" (611)
- Bibliotheken (618)
- COC AF (612)
- COC BG (613)
- COC KG (610)
- COC Paint (307119)
- COC_Bolzen (501)
- Produkt Importe (625)
- SEP_Export (494)
- SEP_Import (493)
- Working folder (232265)

### Under "Projekt MA" (614)
- ADMIN (619)
- Methoden (620)

### Under "Pruefplanung" (512)
- COC AF (513)
- COC BG (514)
- COC KG (515)

### Under "Standardstruktur Logistik" (634)
- Logistikbibliotheken (607)

### Under "Variantenbibliothek" (550)
- Variantenfilter (609)

## Notes

- **Relationship Type:** All relationships use REL_TYPE = 4
- **Circular References:** Some children reference back to the root project (OBJECT_ID 60)
- **Tree Structure:** Stored in REL_COMMON table with FORWARD_OBJECT_ID pointing to parent
- **Children Count:** CHILDREN_VR_ column indicates number of direct children

## Database Tables Used

- **DFPROJECT:** Project definitions
- **COLLECTION_:** Collection/object storage
- **REL_COMMON:** Parent-child relationships (FORWARD_OBJECT_ID = parent, OBJECT_ID = child)
- **SUB_TREE:** Tree structure metadata (if used)
