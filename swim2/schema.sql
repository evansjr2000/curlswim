-- schema.sql --- reference DDL for the shared swim-times database.
--
--   host    100.77.243.69
--   dbname  swimming
--
-- This file is DESCRIPTIVE, not prescriptive.  The database already
-- exists and is shared: a sibling loader populates it from USA
-- Swimming's GetAllTimesForFilters feed, and swim-times (tangled from
-- swim-times.w) adds best-time rows from the BestTimes feed.  The DDL
-- below was dumped from the live database and is kept here so the
-- program's SQL can be read against the schema it actually targets.
-- Applying it to an empty database reproduces that schema; applying it
-- to the live one is a no-op at best and is not part of any workflow.
--
-- What swim-times touches
-- -----------------------
--   swimmer   read; inserted or refreshed by db_swimmer_key().  Keyed
--             by member_id OR full_name, both UNIQUE -- some rows
--             predate the member id, so matching on only one of them
--             finds nothing and then collides on the other.
--   meet      read; inserted by db_meet_key() when a meet name is new.
--             Only meet_name is supplied: meet_id and the dates come
--             from the richer feed this program does not use.
--   swim      read and inserted by db_insert_row().
--   event     read only, as a foreign-key target (event_code).
--   time_standard
--             read only, as a foreign-key target (standard_name).  It
--             holds the seven age-group levels and nothing else, so an
--             elite label from BestTimes -- "Nats", "Trials",
--             "Summer Jrs" -- is written as NULL.  db_standard() does
--             that mapping.
--   course, stroke, age_group, swimmer_alias
--             not touched; included here for completeness because
--             event and swim reference them.
--
-- Two columns deserve a note
-- --------------------------
--   swim.swim_time_id   The primary key, with no default, because it
--             normally holds USA Swimming's own swimTimeId.  BestTimes
--             does not return one, so swim_surrogate_id() derives a
--             stable NEGATIVE id from the leading 63 bits of the
--             SHA-256 of (swimmer_key, event_code, swim_time,
--             swim_date, meet_key).  Negative values cannot collide
--             with the service's positive ids, and the mapping is
--             stable, so re-running a fetch reproduces the same id.
--
--   swim_natural_key    UNIQUE (swimmer_key, event_code, swim_time,
--             swim_date, meet_key) NULLS NOT DISTINCT -- the duplicate
--             guard.  db_insert_row() issues a bare ON CONFLICT DO
--             NOTHING, which absorbs a violation of this constraint
--             (the swim is already recorded) or of the primary key (an
--             improbable surrogate collision) alike, so a re-run is a
--             no-op rather than a page of warnings.
--
-- Note that a swim recorded by both feeds appears twice: the BestTimes
-- rows the sibling loader wrote anonymously carry a NULL swim_date, so
-- the natural key does not match the dated row from
-- GetAllTimesForFilters.  That predates this program's involvement and
-- is left alone.
--
-- ------------------------------------------------------------------
-- Dumped with:
--   pg_dump --schema-only --no-owner --no-privileges \
--           -t swimmer -t swimmer_alias -t meet -t swim -t event \
--           -t course -t stroke -t time_standard -t age_group \
--           postgresql://postgres@100.77.243.69:5432/swimming
-- ------------------------------------------------------------------

--
-- PostgreSQL database dump
--

\restrict nqxFcszd6MSqpb3WJo1znFJjmYHeMr6gGrIKYtoYyraGZQQ88JcQw6bDpVgtFVI

-- Dumped from database version 18.3 (Ubuntu 18.3-1.pgdg26.04+2)
-- Dumped by pg_dump version 18.4

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: age_group; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.age_group (
    age_group_label text NOT NULL,
    age_min smallint NOT NULL,
    age_max smallint NOT NULL,
    sort_order smallint NOT NULL,
    CONSTRAINT age_group_bounds CHECK ((age_min <= age_max))
);


--
-- Name: course; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.course (
    course_code text NOT NULL,
    description text NOT NULL
);


--
-- Name: event; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.event (
    event_code text NOT NULL,
    distance integer NOT NULL,
    stroke_code text NOT NULL,
    course_code text NOT NULL,
    is_canonical boolean DEFAULT false NOT NULL,
    CONSTRAINT event_distance_positive CHECK ((distance > 0))
);


--
-- Name: meet; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.meet (
    meet_key bigint NOT NULL,
    meet_id bigint,
    meet_name text NOT NULL,
    lsc_code text,
    start_date date,
    end_date date,
    CONSTRAINT meet_name_nonempty CHECK ((meet_name <> ''::text))
);


--
-- Name: meet_meet_key_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.meet_meet_key_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: meet_meet_key_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.meet_meet_key_seq OWNED BY public.meet.meet_key;


--
-- Name: stroke; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stroke (
    stroke_code text NOT NULL,
    description text NOT NULL
);


--
-- Name: swim; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.swim (
    swim_time_id bigint NOT NULL,
    swimmer_key bigint NOT NULL,
    event_code text NOT NULL,
    meet_key bigint,
    swim_date date,
    swim_time text NOT NULL,
    seconds double precision,
    swimmer_age smallint,
    age_group_label text,
    standard_name text,
    power_points integer,
    finish_position smallint,
    club_name text,
    session_name text,
    source_endpoint text NOT NULL,
    auth_mode text NOT NULL,
    loaded_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT swim_age_range CHECK (((swimmer_age IS NULL) OR ((swimmer_age >= 3) AND (swimmer_age <= 120)))),
    CONSTRAINT swim_auth_mode_known CHECK ((auth_mode = ANY (ARRAY['authenticated'::text, 'anonymous'::text]))),
    CONSTRAINT swim_seconds_positive CHECK (((seconds IS NULL) OR (seconds > (0)::double precision)))
);


--
-- Name: swimmer; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.swimmer (
    swimmer_key bigint NOT NULL,
    member_id text,
    full_name text NOT NULL,
    birth_date date,
    lsc_code text,
    club_name text,
    first_seen timestamp with time zone DEFAULT now() NOT NULL,
    last_fetched timestamp with time zone,
    CONSTRAINT swimmer_full_name_nonempty CHECK ((full_name <> ''::text))
);


--
-- Name: swimmer_alias; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.swimmer_alias (
    alias text NOT NULL,
    swimmer_key bigint NOT NULL,
    search_query text NOT NULL,
    match_substr text NOT NULL,
    age_min smallint,
    age_max smallint,
    date_min date,
    date_max date,
    label text,
    origin text DEFAULT 'admitted'::text NOT NULL,
    CONSTRAINT swimmer_alias_age_order CHECK (((age_min IS NULL) OR (age_max IS NULL) OR (age_min <= age_max))),
    CONSTRAINT swimmer_alias_date_order CHECK (((date_min IS NULL) OR (date_max IS NULL) OR (date_min <= date_max))),
    CONSTRAINT swimmer_alias_origin CHECK ((origin = ANY (ARRAY['seed'::text, 'admitted'::text])))
);


--
-- Name: swimmer_swimmer_key_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.swimmer_swimmer_key_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: swimmer_swimmer_key_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.swimmer_swimmer_key_seq OWNED BY public.swimmer.swimmer_key;


--
-- Name: time_standard; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.time_standard (
    standard_name text NOT NULL,
    rank smallint NOT NULL
);


--
-- Name: meet meet_key; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meet ALTER COLUMN meet_key SET DEFAULT nextval('public.meet_meet_key_seq'::regclass);


--
-- Name: swimmer swimmer_key; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.swimmer ALTER COLUMN swimmer_key SET DEFAULT nextval('public.swimmer_swimmer_key_seq'::regclass);


--
-- Name: age_group age_group_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.age_group
    ADD CONSTRAINT age_group_pkey PRIMARY KEY (age_group_label);


--
-- Name: course course_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.course
    ADD CONSTRAINT course_pkey PRIMARY KEY (course_code);


--
-- Name: event event_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event
    ADD CONSTRAINT event_pkey PRIMARY KEY (event_code);


--
-- Name: meet meet_meet_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meet
    ADD CONSTRAINT meet_meet_id_key UNIQUE (meet_id);


--
-- Name: meet meet_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meet
    ADD CONSTRAINT meet_pkey PRIMARY KEY (meet_key);


--
-- Name: stroke stroke_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stroke
    ADD CONSTRAINT stroke_pkey PRIMARY KEY (stroke_code);


--
-- Name: swim swim_natural_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.swim
    ADD CONSTRAINT swim_natural_key UNIQUE NULLS NOT DISTINCT (swimmer_key, event_code, swim_time, swim_date, meet_key);


--
-- Name: swim swim_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.swim
    ADD CONSTRAINT swim_pkey PRIMARY KEY (swim_time_id);


--
-- Name: swimmer_alias swimmer_alias_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.swimmer_alias
    ADD CONSTRAINT swimmer_alias_pkey PRIMARY KEY (alias);


--
-- Name: swimmer swimmer_full_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.swimmer
    ADD CONSTRAINT swimmer_full_name_key UNIQUE (full_name);


--
-- Name: swimmer swimmer_member_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.swimmer
    ADD CONSTRAINT swimmer_member_id_key UNIQUE (member_id);


--
-- Name: swimmer swimmer_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.swimmer
    ADD CONSTRAINT swimmer_pkey PRIMARY KEY (swimmer_key);


--
-- Name: time_standard time_standard_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.time_standard
    ADD CONSTRAINT time_standard_pkey PRIMARY KEY (standard_name);


--
-- Name: event_course_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX event_course_idx ON public.event USING btree (course_code);


--
-- Name: meet_name_only_uq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX meet_name_only_uq ON public.meet USING btree (meet_name) WHERE (meet_id IS NULL);


--
-- Name: swim_age_group_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX swim_age_group_idx ON public.swim USING btree (age_group_label);


--
-- Name: swim_age_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX swim_age_idx ON public.swim USING btree (swimmer_age);


--
-- Name: swim_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX swim_date_idx ON public.swim USING btree (swim_date);


--
-- Name: swim_event_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX swim_event_idx ON public.swim USING btree (event_code);


--
-- Name: swim_swimmer_event_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX swim_swimmer_event_idx ON public.swim USING btree (swimmer_key, event_code, seconds);


--
-- Name: swim_swimmer_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX swim_swimmer_idx ON public.swim USING btree (swimmer_key);


--
-- Name: swimmer_alias_swimmer_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX swimmer_alias_swimmer_idx ON public.swimmer_alias USING btree (swimmer_key);


--
-- Name: swimmer_full_name_lower_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX swimmer_full_name_lower_idx ON public.swimmer USING btree (lower(full_name));


--
-- Name: event event_course_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event
    ADD CONSTRAINT event_course_code_fkey FOREIGN KEY (course_code) REFERENCES public.course(course_code);


--
-- Name: event event_stroke_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.event
    ADD CONSTRAINT event_stroke_code_fkey FOREIGN KEY (stroke_code) REFERENCES public.stroke(stroke_code);


--
-- Name: swim swim_age_group_label_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.swim
    ADD CONSTRAINT swim_age_group_label_fkey FOREIGN KEY (age_group_label) REFERENCES public.age_group(age_group_label);


--
-- Name: swim swim_event_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.swim
    ADD CONSTRAINT swim_event_code_fkey FOREIGN KEY (event_code) REFERENCES public.event(event_code);


--
-- Name: swim swim_meet_key_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.swim
    ADD CONSTRAINT swim_meet_key_fkey FOREIGN KEY (meet_key) REFERENCES public.meet(meet_key);


--
-- Name: swim swim_standard_name_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.swim
    ADD CONSTRAINT swim_standard_name_fkey FOREIGN KEY (standard_name) REFERENCES public.time_standard(standard_name);


--
-- Name: swim swim_swimmer_key_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.swim
    ADD CONSTRAINT swim_swimmer_key_fkey FOREIGN KEY (swimmer_key) REFERENCES public.swimmer(swimmer_key) ON DELETE CASCADE;


--
-- Name: swimmer_alias swimmer_alias_swimmer_key_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.swimmer_alias
    ADD CONSTRAINT swimmer_alias_swimmer_key_fkey FOREIGN KEY (swimmer_key) REFERENCES public.swimmer(swimmer_key) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict nqxFcszd6MSqpb3WJo1znFJjmYHeMr6gGrIKYtoYyraGZQQ88JcQw6bDpVgtFVI

