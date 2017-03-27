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

-- Create metadata tables
DROP TABLE IF EXISTS public.tbl_mapps;
CREATE TABLE tbl_mapps
(
 database_name varchar(100) not null,
 table_schema varchar(100) not null,
 table_name varchar(100) not null,
 relnamespace oid not null,
 reloid oid not null,
 topic_name varchar(100) not null,
 create_date timestamp not null default now(),
 create_user varchar(100) not null default current_user,
 remark varchar(1000)
);

ALTER TABLE tbl_mapps ADD CONSTRAINT pk_tbl_mapps PRIMARY KEY(database_name,  table_schema,table_name);

COMMENT ON COLUMN tbl_mapps.database_name is 'DATABASE명';
COMMENT ON COLUMN tbl_mapps.table_schema is '테이블 스키마명';
COMMENT ON COLUMN tbl_mapps.table_name is '테이블명';
COMMENT ON COLUMN tbl_mapps.relnamespace is '테이블 스키마명 OID';
COMMENT ON COLUMN tbl_mapps.reloid is '테이블 OID';
COMMENT ON COLUMN tbl_mapps.topic_name is 'KAFKA TOPIC 명';
COMMENT ON COLUMN tbl_mapps.create_date is '등록일자';
COMMENT ON COLUMN tbl_mapps.create_user is '등록사용자';
COMMENT ON COLUMN tbl_mapps.remark is '비고';

DROP TABLE IF EXISTS public.tbl_mapps_hist;
CREATE TABLE tbl_mapps_hist
(
 database_name varchar(100) not null,
 table_schema varchar(100) not null,
 table_name varchar(100) not null,
 mod_date timestamp not null default now(),
 mod_user varchar(100) not null default current_user,
 mod_type varchar(100) not null,
 relnamespace oid not null,
 reloid oid not null,
 topic_name varchar(100) not null,
 create_date timestamp not null,
 create_user varchar(100) not null,
 remark varchar(1000)
);

ALTER TABLE tbl_mapps_hist ADD CONSTRAINT pk_tbl_mapps_hist PRIMARY KEY(database_name,  table_schema,table_name, mod_date);

COMMENT ON COLUMN tbl_mapps_hist.database_name is 'DATABASE명';
COMMENT ON COLUMN tbl_mapps_hist.table_schema is '테이블 스키마명';
COMMENT ON COLUMN tbl_mapps_hist.table_name is '테이블명';
COMMENT ON COLUMN tbl_mapps_hist.mod_date is '이력날짜';
COMMENT ON COLUMN tbl_mapps_hist.mod_user is '이력수행유저';
COMMENT ON COLUMN tbl_mapps_hist.mod_type is '이력타입';
COMMENT ON COLUMN tbl_mapps_hist.relnamespace is '테이블 스키마명 OID';
COMMENT ON COLUMN tbl_mapps_hist.reloid is '테이블 OID';
COMMENT ON COLUMN tbl_mapps_hist.topic_name is 'KAFKA TOPIC 명';
COMMENT ON COLUMN tbl_mapps_hist.create_date is '등록일자';
COMMENT ON COLUMN tbl_mapps_hist.create_user is '등록사용자';
COMMENT ON COLUMN tbl_mapps_hist.remark is '비고';


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
  CONSTRAINT pk_col_mapps_hist PRIMARY KEY (reloid, column_name)
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

CREATE TABLE kafka_con_config
(
 database_name varchar(100) not null,
 connect_name varchar(100) not null,
 contents json not null,
 create_date timestamp not null,
 create_user varchar(100) not null,
 remark varchar(1000)
);

ALTER TABLE kafka_con_config ADD constraint pk_kafka_con_config PRIMARY KEY(database_name, connect_name);

COMMENT ON COLUMN kafka_con_config.database_name is 'DATABASE명';
COMMENT ON COLUMN kafka_con_config.connect_name is 'kafka-connect 이름';
COMMENT ON COLUMN kafka_con_config.contents is 'configuration';
COMMENT ON COLUMN kafka_con_config.create_date is '등록일자';
COMMENT ON COLUMN kafka_con_config.create_user is '등록사용자';
COMMENT ON COLUMN kafka_con_config.remark is '비고';

