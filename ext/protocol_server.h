#ifndef PROTOCOL_SERVER_H
#define PROTOCOL_SERVER_H

#include "protocol.h"
#include "schema_cache.h"
#include "postgres.h"
#include "replication/output_plugin.h"

int update_frame_with_begin_txn(avro_value_t *frame_val, ReorderBufferTXN *txn);
int update_frame_with_commit_txn(avro_value_t *frame_val, ReorderBufferTXN *txn, XLogRecPtr commit_lsn);
int update_frame_with_insert(avro_value_t *frame_val, schema_cache_t cache, Relation rel, TupleDesc tupdesc, HeapTuple newtuple);
int update_frame_with_update(avro_value_t *frame_val, schema_cache_t cache, Relation rel, HeapTuple oldtuple, HeapTuple newtuple);
int update_frame_with_delete(avro_value_t *frame_val, schema_cache_t cache, Relation rel, HeapTuple oldtuple);
/* K4M : load white columns from col_mapps*/
Oid load_mapping_info(schema_cache_t cache);
/* K4M : update white columns from col_mapps*/
int update_col_mapps(schema_cache_t cache, TupleDesc tupdesc, HeapTuple tuple, int action);

#endif /* PROTOCOL_SERVER_H */
