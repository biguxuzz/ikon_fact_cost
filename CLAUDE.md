# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **1C:ERP configuration extension** named `ikon_cost_Доработки` that implements an **optimized cost accounting algorithm** to solve the N+1 query problem in the standard "Structure of Cost" algorithm. The project uses a batch processing approach that maintains correctness while dramatically improving performance for large datasets.

### Current Version
Version: 0.1.1.226
1C Platform: 8.3.27.1936
Extension Mode: Customization (extends standard 1C:ERP)

## Architecture

### Core Components

1. **Main Algorithm Module**: `CommonModules/СтруктураСебестоимости/Ext/Module.bsl`
   - Extends the base `СтруктураСебестоимости` module
   - Implements dual algorithm support: recursive (original) and batch processing (optimized)
   - Controlled by parameter: `ПараметрыДерева.Вставить("ИспользоватьПакетнуюОбработку", Истина/Ложь)`

2. **Caching System**: `CommonModules/ikon_cost_КэшированиеРасчётов/Ext/Module.bsl`
   - Implements caching of calculation results to avoid recomputation
   - Uses information register `ikon_cost_ДетализацияЗатратСебестоимости`
   - Version-based invalidation when algorithm version updates

3. **Reporting Layer**:
   - Optimized report: `Reports/ikon_cost_ФактическаяСебестоимостьПродукции/Ext/ObjectModule.bsl`
   - Reference report (unchanged): `ФСП/ФактическаяСебестоимостьПродукции/Ext/ObjectModule.bsl`
   - Always compare with reference report for correctness verification

### Algorithm Design

#### Old Algorithm (Recursive)
- Individual queries for each semi-finished product
- N+1 query problem with deep hierarchies
- Considered the "golden standard" for correctness
- `ПараметрыДерева.Вставить("ИспользоватьПакетнуюОбработку", Ложь)`

#### New Algorithm (Batch Processing)
- Processes nodes in batches by level
- Significantly reduces database queries
- Maintains correctness by preserving root product data across levels
- Key principle: `ПартияПродукции` field must contain reference to **root product** on ALL levels
- `ПараметрыДерева.Вставить("ИспользоватьПакетнуюОбработку", Истина)`

### Cycle Protection

Both algorithms use `ПройденныйПуть` table to track processed batches and prevent infinite recursion from circular dependencies (counter releases):

- **Old algorithm**: Removes entries after processing (potential vulnerability for complex cycles)
- **New algorithm**: Keeps entries permanently, adds:
  - Maximum recursion depth limit (50 levels)
  - Cycle logging to event log
  - Statistics collection in `ПараметрыДерева.ОбнаруженныеЦиклы`

## Development Workflow

The project uses a specialized agent-based workflow defined in `.cursor/rules/dev1c.mdc`:

1. **Architect** (`/architect`): Analyzes requirements, determines metadata structure and relationships, creates technical specification
2. **Programmer** (`/programmer`): Implements changes in `CommonModules\СтруктураСебестоимости\Ext\Module.bsl`, updates version
3. **DevOps** (`/devops`): Deploys changes to test database, verifies event log for errors
4. **Tester** (`/tester`): Runs `prod_cost_ext` tool (01.01.2025 - 31.12.2025), compares with reference `prod_cost`
5. **Analyst** (`/analyst`): Deep analysis of correctness and performance

## Key Commands

### Deploy Changes to Test Database
```powershell
& 'C:\Program Files\1cv8\8.3.27.1936\bin\1cv8.exe' DESIGNER /S PGORODILOV.WSL/TEST_ERP_BRZ_01 /NAdmin /LoadConfigFromFiles E:\git\ikon_fact_cost -Extension ikon_cost_Доработки; Start-Sleep -Seconds 60; & 'C:\Program Files\1cv8\8.3.27.1936\bin\1cv8.exe' DESIGNER /S PGORODILOV.WSL/TEST_ERP_BRZ_01 /NAdmin /UpdateDBCfg -Extension ikon_cost_Доработки; Start-Sleep -Seconds 60; & 'C:\Program Files\1cv8\8.3.27.1936\bin\1cv8.exe' DESIGNER /S PGORODILOV.WSL/TEST_ERP_BRZ_01 /NAdmin /ReduceEventLogSize $((Get-Date).AddDays(1).ToString('yyyy-MM-dd')); Start-Sleep -Seconds 60
```

### Test New Algorithm
Run instrument `prod_cost_ext` for period 01.01.2025 - 31.12.2025
Compare results with reference instrument `prod_cost` (old algorithm)

### Check Event Log
Use `execution_log` with current date filter to verify deployment success
Look for absence of `_$Session$_.ConfigExtensionApplyError` events
Note: Event log has +2 hour time offset

## Development Rules

1. **Code Location**: All changes go into `CommonModules\СтруктураСебестоимости\Ext\Module.bsl` only (extension layer)
2. **Reference Report**: Never modify the report in `ФСП/` folder (reference implementation)
3. **Algorithm Choice**: Always use batch processing (`ИспользоватьПакетнуюОбработку = Истина`) - old algorithm is only for reference/comparison
4. **Correctness Standard**: Old algorithm results are always considered correct - new algorithm must return identical results (within rounding tolerance)
5. **Version Management**:
   - Increment version in `Configuration.xml` (last digit: 0.1.0.9 → 0.1.0.10)
   - Record version in first event log message in `ikon_cost_ПараметрыУзлаСКэшем()` function
6. **Event Log Monitoring**: No `_$Session$_.ConfigExtensionApplyError` events with 'Ошибка применения модуля ikon_cost_Доработки' comment

## Critical Implementation Details

### Root Product Data Preservation
The most critical bug that was fixed (in init branch) involved using current-level data instead of root product data. The new algorithm must always:
- Pass root product data through all levels: `АналитикаУчетаПродукции`, `ПартияПродукции`, `АналитикаУчетаПартийПродукции`
- Never use `ТекПартия` fields for root product linkage
- Create new `НовоеОписаниеПродукции` for next level with ROOT product data, not current level data

### Data Flow in Report
Report joins data: `ВТПродукция.ПартияПродукции = ВТЗатраты.ПартияПродукции`
This is why root product linkage is critical - materials on deep levels must link to the original product, not intermediate semi-finished products

## File Structure

```
CommonModules/
├── СтруктураСебестоимости/
│   └── Ext/Module.bsl          # Main algorithm implementation
├── ikon_cost_КэшированиеРасчётов/
│   └── Ext/Module.bsl          # Caching system
Reports/
└── ikon_cost_ФактическаяСебестоимостьПродукции/
    └── Ext/ObjectModule.bsl    # Optimized report
ФСП/
└── ФактическаяСебестоимостьПродукции/
    └── Ext/ObjectModule.bsl    # Reference report (DO NOT MODIFY)
.cursor/
├── agents/                     # Agent definitions (architect, programmer, devops, tester, analyst)
└── rules/dev1c.mdc            # Workflow orchestration rules
```

## Testing

Test results are saved as `test_results_vX.Y.Z.md` files containing:
- Comparison of key metrics (cost, material costs, additional expenses, fixed costs, tax accounting)
- Detailed line-by-line comparison of significant cost items
- Maximum and average discrepancies (must be within rounding tolerance)
- Final verdict: SUCCESS or FAIL

Acceptable discrepancy: <0.01% (rounding tolerance)

## Version History Documentation

Each version change is documented in `__ВЕРСИЯ_X.Y.Z.md` files showing:
- Configuration.xml version change
- Module.bsl event log message update
- Specific changes made

## Performance Optimization Strategy

1. **Batch processing**: Reduces database round trips by processing nodes in levels
2. **Caching layer**: Avoids recomputation of already calculated costs
3. **Lazy initialization**: On-demand resource loading
4. **Reference preservation**: Maintains root product data across levels without re-querying
