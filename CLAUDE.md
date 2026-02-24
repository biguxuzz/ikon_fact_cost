# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **1C:ERP configuration extension** named `ikon_cost_Доработки` that implements an **optimized cost accounting algorithm** to solve N+1 query problem in the standard "Structure of Cost" algorithm. The project uses a batch processing approach that maintains correctness while dramatically improving performance for large datasets.

### Current Version
Version: 0.1.1.276
1C Platform: 8.3.27.1936
Extension Mode: Customization (extends standard 1C:ERP)

## Multi-Agent Development Workflow

The project uses a specialized multi-agent system defined in `.claude/rules/dev1c.mdc`. **All agent definitions are located in `.claude/agents/` folder**.

### Agent Roles

| Agent | Subagent Type | Purpose |
|-------|---------------|---------|
| Architect | `1c-architect` | Analyzes requirements, defines metadata structure, creates technical specification |
| Programmer | `programmer-1c` | Implements code changes in algorithm modules |
| DevOps | `1c-devops-deploy` | Deploys changes to test database, verifies deployment |
| Tester | `1c-tester` | Runs validation reports, compares results with reference |
| Analyst | `1c-analyst` | Deep analysis of correctness and performance |

### Workflow Cycle

```
1. User → 1c-architect (analyze requirements)
   ↓
2. 1c-architect → programmer-1c (create spec → implement)
   ↓
3. programmer-1c → 1c-devops-deploy (deploy to test DB)
   ↓
4. 1c-devops-deploy → 1c-tester (verify functionality)
   ↓
5. 1c-tester → 1c-analyst (analyze results)
   ↓
6. 1c-analyst → User (final verdict)
```

### Critical Platform Interaction Rule

**ONLY** DevOps agent is allowed to interact with 1C platform, and ONLY through `deploy.sh` script.

- **ABSOLUTELY FORBIDDEN**: Never call 1cv8, 1cv8s, LoadConfigFromFiles, UpdateDBCfg, ReduceEventLogSize, or DumpCfg directly
- All other agents use **MCP tools** for 1C interaction:
  - `mcp__gstai_mcp__execution_log` - Check event log
  - `mcp__gstai_mcp__prod_cost` - Run reference report (old algorithm)
  - `mcp__gstai_mcp__prod_cost_ext` - Run optimized report (new algorithm)
  - `mcp__1c-code-metadata-mcp__metadatasearch` - Search metadata
  - `mcp__1c-code-metadata-mcp__codesearch` - Search code
  - `mcp__1c-code-metadata-mcp__helpsearch` - Search help

For complete workflow rules, see **`.claude/rules/dev1c.mdc`** and agent definitions in **`.claude/agents/`**.

### Production Deployment Ban

**STRICTLY FORBIDDEN:**
- Deployment to production database (PROD_ERP) is NOT ALLOWED under any circumstances
- Only test database (TEST_ERP_BRZ_01) may be used for deployment
- Production deployment requires official approval process
- Never execute deployment commands on production systems

**Allowed databases:**
- TEST_ERP_BRZ_01 (test environment only)

**Deployment Safety:**
- ALL deployment operations must use `deploy.sh` script ONLY
- `deploy.sh` performs: LoadConfigFromFiles, UpdateDBCfg, ReduceEventLogSize, DumpCfg
- Script includes proper delays (60 seconds) between steps
- Script order: Load → Update DB → Clean Log → Dump (for production artifact)

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

3. **Background Processing Module**: `CommonModules/ikon_cost_СтруктураСебестоимостиФоновый/Ext/Module.bsl`
   - Performs preliminary cache calculation for specified period in background
   - Main export function: `ПредварительныйРасчётКэшаСебестоимости(ПараметрыВыполнения)`
   - Supports filtering by nomenclature list and organizations
   - Limits progress messages to maximum 100 to avoid performance degradation
   - Returns table with calculation results (nomenclature, success status, duration)

4. **Service Queries Module**: `CommonModules/ikon_cost_СтруктураСебестоимостиСлужебныйЗапросы/Ext/Module.bsl`
   - Service module for SQL query text generation for cost calculation
   - Contains functions extracted from `СтруктураСебестоимости` for better code maintainability
   - Main export function: `ТекстЗапросаЗатратыНаПродукцию(ВыводитьДопРасходы)`
   - Includes multiple helper functions for various cost types (material costs, labor, overhead, etc.)
   - All functions are server-side and exportable

5. **Multi-threaded Recalculation Form**: `DataProcessors/ikon_cost_ПересчётСтруктурыСебестоимости/Forms/Форма/Ext/Form/Module.bsl`
   - Form for launching multi-threaded cost cache recalculation for selected period
   - Uses `ДлительныеОперации.ВыполнитьФункциюВНесколькоПотоков` for parallel processing
   - Splits nomenclature list into batches for parallel execution
   - Default thread count: 8 (configurable)
   - Shows execution progress and results summary
   - Functions:
     * `РазбитьМассивПоПачкам()` - Splits array into batches
     * `НачатьРасчётНаСервере()` - Starts multi-threaded calculation
     * `ЗавершениеРасчётаНаСервере()` - Processes calculation results

6. **Reporting Layer**:
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

## Project Structure

```
CommonModules/
├── СтруктураСебестоимости/
│   └── Ext/Module.bsl          # Main algorithm implementation
├── ikon_cost_КэшированиеРасчётов/
│   └── Ext/Module.bsl          # Caching system
├── ikon_cost_СтруктураСебестоимостиФоновый/
│   └── Ext/Module.bsl          # Background processing module
├── ikon_cost_СтруктураСебестоимостиСлужебныйЗапросы/
│   └── Ext/Module.bsl          # SQL query text generation service
Reports/
└── ikon_cost_ФактическаяСебестоимостьПродукции/
    └── Ext/ObjectModule.bsl    # Optimized report
DataProcessors/
└── ikon_cost_ПересчётСтруктурыСебестоимости/
    └── Forms/Форма/Ext/Form/Module.bsl  # Multi-threaded recalculation form
ФСП/
└── ФактическаяСебестоимостьПродукции/
    └── Ext/ObjectModule.bsl    # Reference report (DO NOT MODIFY)
.claude/
├── agents/                     # Agent definitions (architect, programmer, devops, tester, analyst)
└── rules/dev1c.mdc            # Workflow orchestration rules
.docs/
├── arch/                       # Technical specifications from Architect
│   └── TECH_SPEC_ВЕРСИЯ_X.Y.Z.md
├── test/                       # Test results from Tester
│   └── ВЕРСИЯ_X.Y.Z.md
└── analysis/                   # Analysis reports from Analyst
    └── ANALYSIS_ВЕРСИЯ_X.Y.Z.md
```

## Development Rules

1. **Code Location**: All changes go into `CommonModules\СтруктураСебестоимости\Ext\Module.bsl` primarily (extension layer)
2. **Reference Report**: Never modify the report in `ФСП/` folder (reference implementation)
3. **Algorithm Choice**: Always use batch processing (`ИспользоватьПакетнуюОбработку = Истина`) - old algorithm is only for reference/comparison
4. **Correctness Standard**: Old algorithm results are always considered correct - new algorithm must return identical results (within rounding tolerance <0.01%)
5. **Version Management**:
   - Increment version in `Configuration.xml`
   - Record version in first event log message in `ikon_cost_ПараметрыУзлаСКэшем()` function
6. **Event Log Monitoring**: No `_$Session$_.ConfigExtensionApplyError` events with 'Ошибка применения модуля ikon_cost_Доработки' comment
7. **Platform Interaction**: Use `./deploy.sh` script for deployment, DevOps agent verifies via MCP tools
8. **Production Ban**: NEVER deploy to production, only test database allowed

## Critical Implementation Details

### Root Product Data Preservation
The most critical bug that was fixed (in init branch) involved using current-level data instead of root product data. The new algorithm must always:
- Pass root product data through all levels: `АналитикаУчетаПродукции`, `ПартияПродукции`, `АналитикаУчетаПартийПродукции`
- Never use `ТекПартия` fields for root product linkage
- Create new `НовоеОписаниеПродукции` for next level with ROOT product data, not current level data

### Data Flow in Report
Report joins data: `ВТПродукция.ПартияПродукции = ВТЗатраты.ПартияПродукции`
This is why root product linkage is critical - materials on deep levels must link to the original product, not intermediate semi-finished products

## Testing

Test results are saved in `.docs/test/ВЕРСИЯ_X.Y.Z.md` files containing:
- Comparison of key metrics (cost, material costs, additional expenses, fixed costs, tax accounting)
- Detailed line-by-line comparison of significant cost items
- Maximum and average discrepancies (must be within rounding tolerance)
- Final verdict: SUCCESS or FAIL

Acceptable discrepancy: <0.01% (rounding tolerance)

### Test Parameters
- Period: 01.01.2025 - 31.12.2025
- New algorithm: `prod_cost_ext` MCP tool
- Reference algorithm: `prod_cost` MCP tool
- Compare results for correctness verification

## Version History Documentation

Each version change is documented in `.docs/arch/TECH_SPEC_ВЕРСИЯ_X.Y.Z.md` files showing:
- Configuration.xml version change
- Module.bsl event log message update
- Specific changes made

## Performance Optimization Strategy

1. **Batch processing**: Reduces database round trips by processing nodes in levels
2. **Caching layer**: Avoids recomputation of already calculated costs
3. **Lazy initialization**: On-demand resource loading
4. **Reference preservation**: Maintains root product data across levels without re-querying
5. **Progress limiting**: Limits UI progress messages to maximum 100 to avoid performance degradation

## Key Commands Reference

### Using Agents
Invoke agents via Task tool with appropriate subagent_type:
- `Task(subagent_type="1c-architect", ...)` - Analyze requirements
- `Task(subagent_type="programmer-1c", ...)` - Implement code
- `Task(subagent_type="1c-devops-deploy", ...)` - Deploy to test DB
- `Task(subagent_type="1c-tester", ...)` - Run validation
- `Task(subagent_type="1c-analyst", ...)` - Analyze results

### MCP Tools for Testing
```python
# Run new algorithm report
mcp__gstai_mcp__prod_cost_ext(startDate="2025-01-01", endDate="2025-12-31")

# Run reference report
mcp__gstai_mcp__prod_cost(startDate="2025-01-01", endDate="2025-12-31")

# Check event log (note: +2 hour offset)
mcp__gstai_mcp__execution_log(startDate="2026-02-21T00:00:00", endDate="2026-02-23T23:59:59")
```

### MCP Tools for Metadata Understanding
```python
# Search for metadata objects
mcp__1c-code-metadata-mcp__metadatasearch(query="Справочники.Номенклатура.Реквизиты")

# Search for code
mcp__1c-code-metadata-mcp__codesearch(query="ikon_cost_ПараметрыУзлаСКэшем")

# Search for help
mcp__1c-code-metadata-mcp__helpsearch(query="Себестоимость")
```

### Deployment
```bash
cd /mnt/e/git/ikon_fact_cost
bash deploy.sh
```

Deploy script automatically:
- Reads version from Configuration.xml
- Loads configuration from files
- Updates database structure
- Cleans event log
- Dumps extension to file (production artifact)
- Includes 60-second delays between steps
