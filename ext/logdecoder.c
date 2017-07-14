#include "io_util.h"
#include "protocol_server.h"
#include "oid2avro.h"
#include "error_policy.h"

#include "executor/spi.h" //K4M 
#include "replication/logical.h"
#include "replication/output_plugin.h"
#include "utils/builtins.h"
#include "utils/memutils.h"

/* Entry point when Postgres loads the plugin */
extern void _PG_init(void);
extern void _PG_output_plugin_init(OutputPluginCallbacks *cb);

static void output_avro_startup(LogicalDecodingContext *ctx, OutputPluginOptions *opt, bool is_init);
static void output_avro_shutdown(LogicalDecodingContext *ctx);
static void output_avro_begin_txn(LogicalDecodingContext *ctx, ReorderBufferTXN *txn);
static void output_avro_commit_txn(LogicalDecodingContext *ctx, ReorderBufferTXN *txn, XLogRecPtr commit_lsn);
static void output_avro_change(LogicalDecodingContext *ctx, ReorderBufferTXN *txn, Relation rel, ReorderBufferChange *change);

typedef struct {
    MemoryContext memctx; /* reset after every change event, to prevent leaks */
    avro_schema_t frame_schema;
    avro_value_iface_t *frame_iface;
    avro_value_t frame_value;
    schema_cache_t schema_cache;
    error_policy_t error_policy;
} plugin_state;

extern Oid master_reloid ; /* K4M : reloid of repository table : col_mapps*/
void reset_frame(plugin_state *state);
int write_frame(LogicalDecodingContext *ctx, plugin_state *state);
Oid get_master_reloid(void); /* K4M : reloid of repository table : col_mapps*/

void _PG_init() {
}

void _PG_output_plugin_init(OutputPluginCallbacks *cb) {
    AssertVariableIsOfType(&_PG_output_plugin_init, LogicalOutputPluginInit);
    cb->startup_cb = output_avro_startup;
    cb->begin_cb = output_avro_begin_txn;
    cb->change_cb = output_avro_change;
    cb->commit_cb = output_avro_commit_txn;
    cb->shutdown_cb = output_avro_shutdown;
}

static void output_avro_startup(LogicalDecodingContext *ctx, OutputPluginOptions *opt,
        bool is_init) {
    ListCell *option;

    plugin_state *state = palloc(sizeof(plugin_state));
    ctx->output_plugin_private = state;
    opt->output_type = OUTPUT_PLUGIN_BINARY_OUTPUT;

    state->memctx = AllocSetContextCreate(ctx->context, "Avro decoder context",
            ALLOCSET_DEFAULT_MINSIZE, ALLOCSET_DEFAULT_INITSIZE, ALLOCSET_DEFAULT_MAXSIZE);

    state->frame_schema = schema_for_frame();
    state->frame_iface = avro_generic_class_from_schema(state->frame_schema);
    avro_generic_value_new(state->frame_iface, &state->frame_value);
    state->schema_cache = schema_cache_new(ctx->context);

    foreach(option, ctx->output_plugin_options) {
        DefElem *elem = lfirst(option);
        Assert(elem->arg == NULL || IsA(elem->arg, String));

        if (strcmp(elem->defname, "error_policy") == 0) {
            if (elem->arg == NULL) {
                ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                        errmsg("No value specified for parameter \"%s\"",
                            elem->defname)));
            } else {
                state->error_policy = parse_error_policy(strVal(elem->arg));
            }
        } else {
            ereport(INFO, (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                    errmsg("Parameter \"%s\" = \"%s\" is unknown",
                        elem->defname,
                        elem->arg ? strVal(elem->arg) : "(null)")));
        }
    }
}

static void output_avro_shutdown(LogicalDecodingContext *ctx) {
    plugin_state *state = ctx->output_plugin_private;
    MemoryContextDelete(state->memctx);

    schema_cache_free(state->schema_cache);
    avro_value_decref(&state->frame_value);
    avro_value_iface_decref(state->frame_iface);
    avro_schema_decref(state->frame_schema);
}

static void output_avro_begin_txn(LogicalDecodingContext *ctx, ReorderBufferTXN *txn) {
    plugin_state *state = ctx->output_plugin_private;
    MemoryContext oldctx = MemoryContextSwitchTo(state->memctx);
    reset_frame(state);

    if (update_frame_with_begin_txn(&state->frame_value, txn)) {
        elog(ERROR, "output_avro_begin_txn: Avro conversion failed: %s", avro_strerror());
    }
    if (write_frame(ctx, state)) {
        elog(ERROR, "output_avro_begin_txn: writing Avro binary failed: %s", avro_strerror());
    }

    MemoryContextSwitchTo(oldctx);
    MemoryContextReset(state->memctx);
}

static void output_avro_commit_txn(LogicalDecodingContext *ctx, ReorderBufferTXN *txn,
        XLogRecPtr commit_lsn) {
    plugin_state *state = ctx->output_plugin_private;
    MemoryContext oldctx = MemoryContextSwitchTo(state->memctx);
    reset_frame(state);

    if (update_frame_with_commit_txn(&state->frame_value, txn, commit_lsn)) {
        elog(ERROR, "output_avro_commit_txn: Avro conversion failed: %s", avro_strerror());
    }
    if (write_frame(ctx, state)) {
        elog(ERROR, "output_avro_commit_txn: writing Avro binary failed: %s", avro_strerror());
    }

    MemoryContextSwitchTo(oldctx);
    MemoryContextReset(state->memctx);
}

static void output_avro_change(LogicalDecodingContext *ctx, ReorderBufferTXN *txn,
        Relation rel, ReorderBufferChange *change) {
    int err = 0;
    HeapTuple oldtuple = NULL, newtuple = NULL;
    plugin_state *state = ctx->output_plugin_private;
    MemoryContext oldctx = MemoryContextSwitchTo(state->memctx);
    reset_frame(state);

/* K4M : On start up, set master_reloid */
	if(master_reloid == 0){
		if ((err = SPI_connect()) < 0) {
			elog(ERROR, "bottledwater_export: SPI_connect returned %d", err);
		}
		master_reloid = get_master_reloid();
		load_mapping_info(state->schema_cache);
		SPI_finish();
	}

    switch (change->action) {
        case REORDER_BUFFER_CHANGE_INSERT:
            if (!change->data.tp.newtuple) {
                elog(ERROR, "output_avro_change: insert action without a tuple");
            }
            newtuple = &change->data.tp.newtuple->tuple;
            err = update_frame_with_insert(&state->frame_value, state->schema_cache, rel,
                    RelationGetDescr(rel), newtuple);
            break;

        case REORDER_BUFFER_CHANGE_UPDATE:
            if (!change->data.tp.newtuple) {
                elog(ERROR, "output_avro_change: update action without a tuple");
            }
            if (change->data.tp.oldtuple) {
                oldtuple = &change->data.tp.oldtuple->tuple;
            }
            newtuple = &change->data.tp.newtuple->tuple;
            err = update_frame_with_update(&state->frame_value, state->schema_cache, rel, oldtuple, newtuple);
            break;

        case REORDER_BUFFER_CHANGE_DELETE:
            if (change->data.tp.oldtuple) {
                oldtuple = &change->data.tp.oldtuple->tuple;
            }
            err = update_frame_with_delete(&state->frame_value, state->schema_cache, rel, oldtuple);
            break;
/* K4M : Skip table or column  */
        case REORDER_BUFFER_CHANGE_INTERNAL_SPEC_CONFIRM:
			err = 129;
			break;

        default:
            elog(ERROR, "output_avro_change: unknown change action %d", change->action);
    }
/* K4M : Skip table or column  */
    if (err == 129) {
        elog(INFO, "Skip table: %d", RelationGetRelid(rel));
		MemoryContextSwitchTo(oldctx);
		MemoryContextReset(state->memctx);
		return ;
	} else if (err) {
        elog(INFO, "Row conversion failed: %s", schema_debug_info(rel, NULL));
        error_policy_handle(state->error_policy, "output_avro_change: row conversion failed", avro_strerror());
        /* if handling the error didn't exit early, it should be safe to fall
         * through, because we'll just write the frame without the message that
         * failed (so potentially it'll be an empty frame)
         */
    }
    if (write_frame(ctx, state)) {
        error_policy_handle(state->error_policy, "output_avro_change: writing Avro binary failed", avro_strerror());
    }

    MemoryContextSwitchTo(oldctx);
    MemoryContextReset(state->memctx);
}

void reset_frame(plugin_state *state) {
    if (avro_value_reset(&state->frame_value)) {
        elog(ERROR, "Avro value reset failed: %s", avro_strerror());
    }
}

int write_frame(LogicalDecodingContext *ctx, plugin_state *state) {
    int err = 0;
    bytea *output = NULL;

    check(err, try_writing(&output, &write_avro_binary, &state->frame_value));

    OutputPluginPrepareWrite(ctx, true);
    appendBinaryStringInfo(ctx->out, VARDATA(output), VARSIZE(output) - VARHDRSZ);
    OutputPluginWrite(ctx, true);

    pfree(output);
    return err;
}

/* K4M : get master_reloid  */
Oid get_master_reloid(void) {
	Oid ret;
	bool is_null = false;
	ret = SPI_exec("select oid from pg_class where relname = 'col_mapps'", 1);
    if (ret > 0 && SPI_tuptable != NULL && SPI_processed > 0){
		if(SPI_processed > 0){
			TupleDesc tupdesc = SPI_tuptable->tupdesc;
			SPITupleTable *tuptable = SPI_tuptable;
			HeapTuple tuple = tuptable->vals[0];
			ret = DatumGetObjectId(SPI_getbinval(tuple, tupdesc, 1, &is_null));
			Assert(!isnull);
		}
    }
    else {
        ret = 0;
    }
	return ret;
}
