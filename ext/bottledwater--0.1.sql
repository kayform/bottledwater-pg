-- Complain if script is sourced in psql, rather than via CREATE EXTENSION.
\echo Use "CREATE EXTENSION bottledwater" to load this file. \quit

CREATE OR REPLACE FUNCTION bottledwater_key_schema(name) RETURNS text
    AS 'bottledwater', 'bottledwater_key_schema' LANGUAGE C VOLATILE STRICT;

CREATE OR REPLACE FUNCTION bottledwater_row_schema(name) RETURNS text
    AS 'bottledwater', 'bottledwater_row_schema' LANGUAGE C VOLATILE STRICT;

CREATE OR REPLACE FUNCTION bottledwater_frame_schema() RETURNS text
    AS 'bottledwater', 'bottledwater_frame_schema' LANGUAGE C VOLATILE STRICT;

DROP DOMAIN IF EXISTS bottledwater_error_policy;
CREATE DOMAIN bottledwater_error_policy AS text
    CONSTRAINT bottledwater_error_policy_valid CHECK (VALUE IN (
        -- these values should match the constants defined in protocol.h
        'log',
        'exit'
    ));

CREATE OR REPLACE FUNCTION bottledwater_export(
        table_pattern text    DEFAULT '%',
        allow_unkeyed boolean DEFAULT false,
        error_policy bottledwater_error_policy DEFAULT 'exit'
    ) RETURNS setof bytea
    AS 'bottledwater', 'bottledwater_export' LANGUAGE C VOLATILE STRICT;

-- Create column mappng tables
DROP TABLE IF EXISTS public.col_mapps;
CREATE TABLE public.col_mapps
(
  reloid oid NOT NULL,
  column_name character varying(100) NOT NULL,
  colseq integer NOT NULL,
  create_date timestamp without time zone NOT NULL DEFAULT now(),
  create_user character varying(100) NOT NULL DEFAULT "current_user"(),
  remark character varying(1000),
  CONSTRAINT pk_col_mapps PRIMARY KEY (reloid, column_name)
);

COMMENT ON COLUMN col_mapps.reloid is '테이블 OID';
COMMENT ON COLUMN col_mapps.column_name is '컬럼명';
COMMENT ON COLUMN col_mapps.colseq is '컬럼순번';
COMMENT ON COLUMN col_mapps.create_date is '등록일자';
COMMENT ON COLUMN col_mapps.create_user is '등록사용자';
COMMENT ON COLUMN col_mapps.remark is '비고';

-- Create column mappng history tables
DROP TABLE IF EXISTS public.col_mapps_hist;
CREATE TABLE public.col_mapps_hist
(
  reloid oid NOT NULL,
  column_name character varying(100) NOT NULL,
  colseq integer NOT NULL,
  create_date timestamp without time zone NOT NULL DEFAULT now(),
  create_user character varying(100) NOT NULL DEFAULT "current_user"(),
  mod_date timestamp not null default now(),
  mod_user varchar(100) not null default current_user,
  mod_type varchar(100) not null,
  remark character varying(1000),
  CONSTRAINT pk_col_mapps PRIMARY KEY (reloid, column_name)
);

COMMENT ON COLUMN col_mapps_hist.reloid is '테이블 OID';
COMMENT ON COLUMN col_mapps_hist.column_name is '컬럼명';
COMMENT ON COLUMN col_mapps_hist.colseq is '컬럼순번';
COMMENT ON COLUMN col_mapps_hist.create_date is '등록일자';
COMMENT ON COLUMN col_mapps_hist.create_user is '등록사용자';
COMMENT ON COLUMN col_mapps_hist.mod_date is '이력날짜';
COMMENT ON COLUMN col_mapps_hist.mod_user is '이력수행유저';
COMMENT ON COLUMN col_mapps_hist.mod_type is '이력타입';
COMMENT ON COLUMN col_mapps_hist.remark is '비고';

