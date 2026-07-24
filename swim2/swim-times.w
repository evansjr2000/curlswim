% Limbo: inline-code macro for prose (cwebmac is plain TeX, so \code
% must be defined here rather than relying on a LaTeX definition).
\def\code#1{\.{#1}}

@* Swim Times.

This is a program written using Donald Knuth's literate programming paradigm (see more below).
It fetches best short-course yard (SCY) and long-course meter (LCM) times
for a roster of swimmers.  The roster began with four family swimmers:

\medskip
$${\vbox{
\item{} {\bf Stella Julianna Evans} --- 10~\&~Under Girls

\item{} {\bf Kalea Rose Benavente} --- 13--14 Girls

\item {} {\bf Kenneth Ray Evans} --- 11--12 Boys

\item{} {\bf Keith Santiago Evans} --- 11--12 Boys
}}$$

\medskip\noindent
and now also covers Katie Ledecky (as age-group windows) and the full
College~Area Swim~Team (CAST) roster listed in the |SWIMMERS| table of
the main program.  Each swimmer carries a unique {\it id\/} used to
select her on the command line; the ids are enumerated in the software
requirements specification (\.{swim-times-srs.tex}).
Thirty-one events are reported for each swimmer.
Short-course yard (SCY) events: 50, 100, 200, 500, 1000, and 1650~Freestyle;
50 and 100~Butterfly; 50 and 100~Backstroke; 50 and 100~Breaststroke;
and 100 and 200~Individual Medley.
Long-course meter (LCM) events: 50, 100, 200, 400, 800, and 1500~Freestyle;
50, 100, and 200~Butterfly; 50, 100, and 200~Backstroke;
50, 100, and 200~Breaststroke; and 200 and 400~Individual Medley.
Data is fetched live from the USA~Swimming data hub's public REST
services at \.{times-api.usaswimming.org}.

@ {\bf How it works.}  The data hub was formerly powered by a Sisense
JAQL analytics API; it has since moved to first-party REST services,
and this program follows.  We make two kinds of requests:

\medskip\item{1.} A {\it member search\/} (\.{GetMembersForFilters}) to
  resolve the swimmer's |memberId|, given a name string and a substring
  to match the returned full name.

\item{2.} A {\it best-times fetch\/} (\.{POST /BestTimes}) issued once
  per stroke-and-distance pair; each record delivers a stroke, distance,
  course, and formatted time --- from which the event code (e.g.\ \.{100
  FR SCY}) is reassembled --- together with the swim date, meet name,
  and the motivational standard attained (\.{B}, \.{BB}, \.{A}, \.{AA},
  \.{AAA}, \.{AAAA}, or an elite label such as \.{Nats} or \.{Trials}).
\medskip

All HTTP communication is handled by \.{libcurl}.  JSON responses are
scanned with simple string operations rather than a full parse tree.

@ {\bf Literate programming.}
Donald Knuth introduced {\it literate programming\/} in 1984 as a way of
writing software that is meant to be read by human beings first and executed
by computers second.  Rather than annotating code with comments, a literate
program interweaves prose and code in a single source document.  The prose
explains the {\it why\/}---the motivation, the design decisions, the
mathematical reasoning---while the code expresses the {\it how}.  The two
live together in one file (conventionally given the extension \.{.w}) and
are separated only at build time by two companion tools: \.{ctangle} and
\.{cweave}.

@ {\bf ctangle.}
\.{ctangle} is the {\it tangling\/} tool.  It reads a \.{.w} source file
and extracts the C~code sections, assembling them in the order dictated
by named chunk references rather than the order in which they appear in
the document.  The result is a plain
\.{.c} file that a standard C~compiler can process without any knowledge
of literate programming.  In this project, running
$$\.{ctangle swim-times.w}$$
produces \.{swim-times.c}, which is then compiled with \.{cc} and
linked against \.{libcurl} to create the \.{swim-times} executable.
The generated \.{.c} file should be treated as a build artefact: the
\.{.w} file is the true source of record.

@ {\bf cweave.}
\.{cweave} is the {\it weaving\/} tool.  It reads the same \.{.w} source
and produces a \.{.tex} file formatted for \.{pdftex} using the
\.{cwebmac} macro package.  \.{cweave} pretty-prints all C~code with
bold keywords, italic identifiers, and cross-references, and numbers every
named chunk so the reader can follow the program's logical structure
independently of its physical layout.  An index of identifiers and a table
of contents are generated automatically.  Running
$$\.{cweave swim-times.w}$$
produces \.{swim-times.tex}; running \.{pdftex} on that file yields the
typeset documentation you are reading now.

@ {\bf Compilation.}  After tangling with \.{ctangle}:
$$\.{gcc -O2 -o swim-times swim-times.c \$(curl-config --libs)}$$

@ {\bf Program structure.}  The top-level arrangement of the tangled
output is:

@c
@<Includes@> @/
@<Global constants@> @/
@<Option flags@> @/
@<Type definitions@> @/
@<HTTP utilities@> @/
@<JSON scanner@> @/
@<Database pipe@> @/
@<Person lookup@> @/
@<Times fetch@> @/
@<Offline fetch@> @/
@<Main function@>

@* Includes and constants.

@ @<Includes@>=
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include <curl/curl.h>
#include <libpq-fe.h>

@ |TIMES_API| is the base URL of the USA~Swimming public times service
that backs \.{data.usaswimming.org}.  |EVENTS| lists all
event codes we query: twelve short-course yard (SCY) events plus
two additional SCY distance events (1000~FR and 1650~FR) and seventeen
long-course meter (LCM) events, for a total of thirty-one.

The global constants are split into three sub-modules so that no
single module exceeds twenty-four lines.

@<Global constants@>=
@<Numeric constants@>
@<Data hub credentials@>
@<Event table@>

@ The two numeric limits used throughout the program.

@<Numeric constants@>=
#define NUM_EVENTS 31
#define MAX_TIMES  200

@ The base URL of the times service.  Note there is deliberately no
hard-coded bearer token here.  The USA~Swimming data hub retired the
Sisense JAQL API this program originally targeted (its embedded token
now returns \.{401 db\_unauthorized}, and the current front-end no
longer exposes any Sisense credential).  The replacement REST services
at \.{times-api.usaswimming.org} authenticate anonymous callers not
with a bearer token but with three custom headers --- |Usas-Sub-Id:
Anonymous|, |AppName: DataHub|, and a client-generated |Device-Id|.
The |Device-Id| is minted at run time by |build_device_id| (see the
HTTP utilities), so the ``token'' is obtained dynamically on every run
rather than baked into the source.

@<Data hub credentials@>=
static const char TIMES_API[] =
    "https://times-api.usaswimming.org/swims/TimesSearch";

@ The event-code table is split into SCY and LCM sub-lists so the
array initialiser fits within the line limit.

@<Event table@>=
static const char *EVENTS[NUM_EVENTS] = {
    @<SCY events@>
    @<LCM events@>
};

@ The fourteen short-course yard event codes.

@<SCY events@>=
"50 FR SCY",  "100 FR SCY", "200 FR SCY", "500 FR SCY",
"1000 FR SCY", "1650 FR SCY",
"50 FL SCY",  "100 FL SCY",
"50 BK SCY",  "100 BK SCY",
"50 BR SCY",  "100 BR SCY",
"100 IM SCY", "200 IM SCY",

@ The seventeen long-course meter event codes.

@<LCM events@>=
"50 FR LCM",   "100 FR LCM",  "200 FR LCM",  "400 FR LCM",
"800 FR LCM",  "1500 FR LCM",
"50 FL LCM",   "100 FL LCM",  "200 FL LCM",
"50 BK LCM",   "100 BK LCM",  "200 BK LCM",
"50 BR LCM",   "100 BR LCM",  "200 BR LCM",
"200 IM LCM",  "400 IM LCM"

@ The program accepts two optional flags on the command line.

The \.{-o} flag takes a comma-separated list of one or more tokens.
A token is either one of four {\it behaviour keywords\/} or a
{\it swimmer id\/}:
\medskip
\item{$\bullet$} \.{fastest} --- print only the single fastest time per event.
\item{$\bullet$} \.{csv} --- emit CSV lines (swimmer name on every line) instead of a table.
\item{$\bullet$} \.{store} --- write each row to the local Postgres
    database \.{swim-times} via \.{libpq}; combine with \.{csv} to also
    print to the terminal.
\item{$\bullet$} \.{offline} --- skip all network calls; read times from
    the local Postgres \.{swim-times} database instead.
\medskip\noindent
Any other token is treated as a swimmer id (e.g.\ \.{stella}, \.{kalea},
\.{ledecky14}, \.{glass-layla}); see the |SWIMMERS| roster for the full
list.  When no swimmer id is given every swimmer is processed.
Tokens may be combined, e.g.\ \.{-o stella,fastest} or
\.{-o kalea,csv,store}.
When no swimmer keyword is specified all swimmers (subject to mode) are shown.

The \.{-e} flag takes one or more comma-separated event codes
(e.g.\ \.{-e "100 FR SCY,50 FL LCM"}) and restricts output to those events
only.  The flag may also be repeated (e.g.\ \.{-e "100 FR SCY" -e "50 FL LCM"}).
When \.{-e} is omitted all thirty-one events are reported.

If no options are given at all the program prints a usage message and exits.

@<Option flags@>=
#define OPT_FASTEST   (1<<0)  /* print only the single fastest time       */
#define OPT_CSV       (1<<1)  /* emit CSV lines instead of a table        */
#define OPT_STORE     (1<<2)  /* also persist rows to Postgres            */
#define OPT_OFFLINE   (1<<3)  /* read from Postgres, skip network         */

@ These are the behaviour flags (how to render or where to read/write).
Swimmer {\it selection\/}---which people to fetch---is no longer encoded
as one bit per swimmer, because the roster now holds several dozen
entries and would overflow the flag word.  Instead each swimmer carries
a unique string |id| (see the |Swimmer| record) and any \.{-o} token
that is not one of the four behaviour keywords above is treated as a
swimmer id and pushed onto |g_sel|.  When |g_nsel| is zero every swimmer
is processed; otherwise only those whose |id| appears in |g_sel|.

@<Option flags@>+=
#define MAX_SEL 64            /* max distinct swimmer ids selectable at once */
static int         g_opts    = 0;  /* behaviour flags; see above            */
static const char *g_sel[MAX_SEL]; /* selected swimmer ids (heap copies)    */
static int         g_nsel    = 0;  /* number of entries in |g_sel|          */
static char g_events[NUM_EVENTS][32]; /* event codes requested via \.{-e}  */
static int  g_nevents = 0;  /* number of entries in |g_events|             */

@* Data structures.

@ A |Buffer| holds a dynamically-grown heap string.  \.{libcurl}
appends each response chunk to it via the write callback.

@<Type definitions@>=
typedef struct {
    char  *data;
    size_t size;
} Buffer;

@ A |TimeRow| records one swim result.  |sort_key| is the swim time in
seconds (smaller is faster), computed by |time_to_seconds|; |time| is
the formatted string (e.g.\ \.{1:02.45}); |date| is the swim date
formatted as \.{YYYY-MM-DD}; |standard| is the motivational standard
attained (e.g.\ \.{B}, \.{BB}, \.{A}); and |meet| is the meet name.
The \.{BestTimes} feed populates every field; only when a swim earned
no motivational standard is |standard| left empty.

@<Type definitions@>+=
typedef struct {
    double sort_key;
    char   time[32];
    char   date[16];
    char   standard[48];
    char   meet[256];
} TimeRow;

@ A |Swimmer| record holds the per-swimmer search parameters: a query
string sent to the person-search API, a lower-case substring used to
identify the correct row, a flag bit used to filter output, and an
optional age window expressed as ISO~\.{YYYY-MM-DD} dates.  The
typedef lives in this section (rather than next to the |SWIMMERS|
array in main) so that |offline_fetch| can reference it without a
forward declaration.

@<Type definitions@>+=
typedef struct {
    const char *id;            /* unique selection id, e.g.\ "stella"   */
    const char *search_query;  /* Name string to search for             */
    const char *match_substr;  /* Lower-case substring to match         */
    const char *date_min;      /* NULL or "YYYY-MM-DD" inclusive lower  */
    const char *date_max;      /* NULL or "YYYY-MM-DD" inclusive upper  */
} Swimmer;

@* HTTP utilities.

@ The \.{libcurl} write callback appends each incoming chunk to a
|Buffer|, growing the allocation as needed.  It maintains a null
terminator so the buffer can always be treated as a C string.

@<HTTP utilities@>=
static size_t write_cb(void *ptr, size_t size, size_t nmemb, void *ud)
{
    Buffer *b = (Buffer *)ud;
    size_t  n = size * nmemb;
    char   *p = realloc(b->data, b->size + n + 1);
    if (!p) return 0;
    b->data = p;
    memcpy(b->data + b->size, ptr, n);
    b->size += n;
    b->data[b->size] = '\0';
    return n;
}

@ |base64| encodes a null-terminated string into standard base64.  It is
used only to shape the |Device-Id| header, so a compact implementation
that never overflows |out| is all that is required.

@<HTTP utilities@>+=
static const char B64[] =
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static void base64(const char *in, char *out, size_t out_sz)
{
    size_t len = strlen(in), i = 0, o = 0;
    while (i + 3 <= len && o + 4 < out_sz) {
        unsigned t = ((unsigned char)in[i]   << 16) |
                     ((unsigned char)in[i+1] <<  8) |
                      (unsigned char)in[i+2];
        out[o++] = B64[(t>>18)&63]; out[o++] = B64[(t>>12)&63];
        out[o++] = B64[(t>> 6)&63]; out[o++] = B64[t&63];
        i += 3;
    }
    if (len > i && o + 4 < out_sz) {
        size_t rem = len - i;
        unsigned t = (unsigned char)in[i] << 16;
        if (rem == 2) t |= (unsigned char)in[i+1] << 8;
        out[o++] = B64[(t>>18)&63];        out[o++] = B64[(t>>12)&63];
        out[o++] = rem==2 ? B64[(t>>6)&63] : '='; out[o++] = '=';
    }
    out[o] = '\0';
}

@ |device_id| returns the cached |Device-Id| value the times service
requires, building it once on first use.  We reproduce the shape the
data hub's front-end produces: base64 of \.{"platform - vendor -
fingerprint - millis"}, then the first five characters repeated after
the fifteenth.  The server validates only the format, so a per-run
fingerprint (process id plus clock) is sufficient.

@<HTTP utilities@>+=
static const char *device_id(void)
{
    static char id[512];
    if (id[0]) return id;
    char raw[128], n[256];
    long now = (long)time(NULL);
    snprintf(raw, sizeof raw, "Linux - curlswim - %lx%lx - %ld000",
             (unsigned long)getpid(), (unsigned long)now, now);
    base64(raw, n, sizeof n);
    snprintf(id, sizeof id, "%.15s%.5s%s", n, n, n + 15);
    return id;
}

@ |http_request| performs one request --- a |GET| when |body| is |NULL|,
otherwise a |POST| carrying |body| --- and returns the response as a
null-terminated heap string, or |NULL| on failure.  The caller frees the
result.  Every request carries the anonymous data-hub headers instead of
a bearer token.

@<HTTP utilities@>+=
static char *http_request(const char *url, const char *body)
{
    @<Initialize curl handle@>
    @<Issue HTTP request and return@>
}

@ The easy handle is created, the anonymous auth headers are assembled,
and all curl options are configured before the request is issued.

@<Initialize curl handle@>=
CURL *curl = curl_easy_init();
if (!curl) return NULL;

Buffer buf = {NULL, 0};

char dev_hdr[560];
snprintf(dev_hdr, sizeof dev_hdr, "Device-Id: %s", device_id());

struct curl_slist *hdrs = NULL;
hdrs = curl_slist_append(hdrs, "Content-Type: application/json");
hdrs = curl_slist_append(hdrs, "AppName: DataHub");
hdrs = curl_slist_append(hdrs, "Usas-Sub-Id: Anonymous");
hdrs = curl_slist_append(hdrs, dev_hdr);

curl_easy_setopt(curl, CURLOPT_URL,           url);
curl_easy_setopt(curl, CURLOPT_HTTPHEADER,    hdrs);
if (body) curl_easy_setopt(curl, CURLOPT_POSTFIELDS, body);
curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_cb);
curl_easy_setopt(curl, CURLOPT_WRITEDATA,     &buf);

@ The request is executed; on success the accumulated buffer is returned
to the caller; on failure the partial buffer is freed and |NULL| is returned.

@<Issue HTTP request and return@>=
CURLcode rc = curl_easy_perform(curl);
curl_slist_free_all(hdrs);
curl_easy_cleanup(curl);

if (rc != CURLE_OK) { free(buf.data); return NULL; }
return buf.data;

@* JSON scanner.

@ The REST responses are JSON arrays of objects with named fields.  A
member-search row looks like
$$\hbox{\.{{"memberId":"6CD35348E5824C","fullName":"Katie Genevieve Ledecky",\dots}}}$$
and a best-times row like
$$\hbox{\.{{"strokeAbbreviation":"FR","distance":50,"courseCode":"SCY","swimTime":"22.64r"}}}$$

Rather than build a full parse tree we scan forward for a named key and
extract the immediately following value, advancing a position pointer.
The scanner is format-agnostic: it served the old Sisense
|"text"|/|"data"| cells and serves these named fields unchanged.

@ |scan_string| finds the first |"key"| at or after |*pos|, copies the
string value that follows into |out| (at most |max_len-1| bytes), and
advances |*pos| past it.  Returns 1 on success, 0 if the key is absent.

@<JSON scanner@>=
static int scan_string(const char *key, const char **pos,
                       char *out, size_t max_len)
{
    char needle[128];
    snprintf(needle, sizeof needle, "\"%s\"", key);
    const char *p = strstr(*pos, needle);
    if (!p) return 0;
    p += strlen(needle);
    while (*p == ' ' || *p == ':') p++;
    if (*p != '"') return 0;
    p++;
    const char *e = strchr(p, '"');
    if (!e) return 0;
    size_t len = (size_t)(e - p);
    if (len >= max_len) len = max_len - 1;
    memcpy(out, p, len);
    out[len] = '\0';
    *pos = e + 1;
    return 1;
}

@ Numeric fields in these feeds (\.{distance}, ages, ids) are not needed
by the scanner: every value the program consumes --- meet name, event
code, date, time, and standard --- arrives as a JSON string, so a single
string extractor suffices.

@* Database connection.

@ The \.{store} option streams rows into the local Postgres database
\.{swim-times}; the \.{offline} option reads previously-stored rows
back.  Both reach Postgres {\it programmatically\/} via the standard
client library \.{libpq} --- no \.{psql} child process or wrapper
script is involved (this is requirement~\#3 of \.{requirements4.txt}:
``Access the Postgres database programmatically, not through scripts'').
A connection string can be supplied via the |SWIM_TIMES_PGCONNINFO|
environment variable; if unset the program connects to a local
container with the keyword string
\.{dbname=swim-times user=postgres host=localhost port=5432}.
Per-row inserts use \.{INSERT \dots\ ON CONFLICT \dots\ DO NOTHING}
keyed on the unique tuple
\.{(swimmer, event, swim\_time, swim\_date, meet)} so a duplicate
silently no-ops without aborting the surrounding work
(requirement~\#4: ``check for duplicates before adding \dots\ and
recover appropriately'').

@<Database pipe@>=
@<Resolve connection string@>
@<Open and close DB connection@>
@<Insert one row@>

@ |db_conn_string| returns the libpq connection string.  Override
at runtime with |SWIM_TIMES_PGCONNINFO|.

@<Resolve connection string@>=
static const char *db_conn_string(void)
{
    const char *e = getenv("SWIM_TIMES_PGCONNINFO");
    return (e && *e)
        ? e
        : "dbname=swim-times user=postgres host=localhost port=5432";
}

@ |db_open| opens a libpq connection and prepares the parameterised
\.{INSERT \dots\ ON CONFLICT DO NOTHING} statement that all
\code{store} writes use.  |db_close| releases the connection.  Both
are idempotent.  The \.{ON CONFLICT} clause keys on the same unique
constraint declared by \.{schema.sql}, so a duplicate row is a
no-op rather than an error.

@<Open and close DB connection@>=
static PGconn *db_conn = NULL;
#define DB_INSERT_STMT "swim_times_insert_v1"
@<Open DB connection@>
@<Close DB connection@>

@ Connection establishment.  A failure is non-fatal here: the caller
chooses whether to abort.  In \code{store} mode the program continues
without persisting; in \code{offline} mode the caller bails out.

@<Open DB connection@>=
static int db_open(void)
{
    db_conn = PQconnectdb(db_conn_string());
    if (PQstatus(db_conn) != CONNECTION_OK) {
        fprintf(stderr,
            "Warning: libpq connection failed: %s",
            PQerrorMessage(db_conn));
        PQfinish(db_conn); db_conn = NULL;
        return 0;
    }
    @<Prepare insert statement@>
    return 1;
}

@ Tear-down.

@<Close DB connection@>=
static void db_close(void)
{
    if (db_conn) { PQfinish(db_conn); db_conn = NULL; }
}

@ The prepared insert.  Date and float casts let us pass every
parameter as a text string; libpq does the parsing.

@<Prepare insert statement@>=
PGresult *r = PQprepare(db_conn, DB_INSERT_STMT,
    "INSERT INTO swim_times "
    "(swimmer,event,swim_time,swim_date,standard,meet,sort_key) "
    "VALUES ($1,$2,$3,$4::date,$5,$6,$7::float8) "
    "ON CONFLICT (swimmer,event,swim_time,swim_date,meet) "
    "DO NOTHING", 7, NULL);
if (PQresultStatus(r) != PGRES_COMMAND_OK) {
    fprintf(stderr, "Warning: prepare failed: %s",
        PQerrorMessage(db_conn));
    PQclear(r); PQfinish(db_conn); db_conn = NULL;
    return 0;
}
PQclear(r);

@ |db_insert_row| executes the prepared statement once for one
\code{TimeRow}.  A duplicate hits the \.{ON CONFLICT DO NOTHING}
branch and is silently absorbed; any other failure logs a warning
but does not abort the run.  An empty |date|, |standard|, or |meet| is
passed as a SQL |NULL| (a |NULL| pointer in the value array) so the
\.{\$4::date} cast does not choke on an empty string; the best-times
feed leaves these fields empty.

@<Insert one row@>=
static void db_insert_row(const char *swimmer, const char *event,
                          const TimeRow *r)
{
    if (!db_conn) return;
    char sk[64];
    snprintf(sk, sizeof sk, "%g", r->sort_key);
    const char *vals[7] = {
        swimmer, event, r->time,
        r->date[0]     ? r->date     : NULL,
        r->standard[0] ? r->standard : NULL,
        r->meet[0]     ? r->meet     : NULL, sk
    };
    PGresult *res = PQexecPrepared(db_conn, DB_INSERT_STMT,
                                   7, vals, NULL, NULL, 0);
    if (PQresultStatus(res) != PGRES_COMMAND_OK)
        fprintf(stderr, "Warning: insert failed: %s",
            PQerrorMessage(db_conn));
    PQclear(res);
}

@* Person lookup. |lookup_member_id| posts a member search for
|search_query| and scans the result records for one whose full name
contains |match_substr| (after lower-casing).  It returns the
matching swimmer's |memberId| as a heap string (an alphanumeric token
such as \.{6CD35348E5824C}, {\it not\/} the old numeric PersonKey) and,
optionally, the full name in |*out_name|.  Returns |NULL| on failure.
The function body is split into five sub-modules.

@
@<Person lookup@>=
static char *lookup_member_id(const char *search_query,
                              const char *match_substr,
                              const char **out_name)
{
    @<Build person-search URL@>
    @<Build person-search body@>
    @<Issue person-search request@>
    @<Scan person-search result@>
    @<Return person-search result@>
}

@ The URL addresses the member-search endpoint.

@<Build person-search URL@>=
char url[512];
snprintf(url, sizeof url, "%s/GetMembersForFilters", TIMES_API);

@ The request body is a |SFPersonSearchFilters| object; only the free-text
|name| field is needed.  The service matches |name| against member full
names, so a distinctive surname keeps the result set small.

@<Build person-search body@>=
char body[512];
snprintf(body, sizeof body, "{\"name\":\"%s\"}", search_query);

@ The HTTP POST is issued; a |NULL| response is a fatal error.

@<Issue person-search request@>=
char *resp = http_request(url, body);
if (!resp) {
    fputs("Error: person lookup request failed\n", stderr);
    return NULL;
}

@ The response is a JSON array of member objects.  Records are scanned
until one whose lower-cased full name contains |match_substr| is found;
its |memberId| is duplicated.  The loop body is a separate sub-chunk so
the outer scanner stays inside the twenty-four line limit.

@<Scan person-search result@>=
char *key  = NULL;
char *name = NULL;
const char *p = resp;

while (p) {
    @<Match one person row@>
}

@ Within each record |memberId| precedes |fullName|, so we read the id
first, then the name; if the name matches we keep the id already in hand.

@<Match one person row@>=
char member[64];
if (!scan_string("memberId", &p, member, sizeof member)) break;

char full_name[256];
if (!scan_string("fullName", &p, full_name, sizeof full_name)) break;

char lower[256];
size_t flen = strlen(full_name);
for (size_t i = 0; i <= flen; i++)
    lower[i] = (char)(full_name[i] >= 'A' && full_name[i] <= 'Z'
                      ? full_name[i] + 32 : full_name[i]);

if (strstr(lower, match_substr)) {
    key  = strdup(member);
    name = strdup(full_name);
    break;
}

@ The response buffer is freed, a diagnostic is printed on failure, and
the |memberId| (or |NULL|) is returned.

@<Return person-search result@>=
free(resp);
if (!key)
    fprintf(stderr, "Error: swimmer \"%s\" not found\n", search_query);
if (out_name) *out_name = name;
else           free(name);
return key;

@* Times fetch.

@ |insertion_sort| sorts |n| |TimeRow| records in-place by |sort_key|
ascending (smallest = fastest time).  A swimmer's career rarely exceeds
a few dozen entries per event, so $O(n^2)$ is entirely adequate.

@<Times fetch@>=
static void insertion_sort(TimeRow *rows, int n)
{
    for (int i = 1; i < n; i++) {
        TimeRow tmp = rows[i];
        int j = i - 1;
        while (j >= 0 && rows[j].sort_key > tmp.sort_key) {
            rows[j + 1] = rows[j];
            j--;
        }
        rows[j + 1] = tmp;
    }
}

@ |time_to_seconds| converts a formatted swim time (\.{"22.64r"},
\.{"1:40.36"}, \.{"14:59.62"}) to a |double| number of seconds, used as
the sort key.  Colon-separated groups are accumulated sexagesimally; any
trailing flag character (such as the \.{r} marking a relay lead-off) is
ignored.

@<Times fetch@>+=
static double time_to_seconds(const char *t)
{
    double total = 0;
    char buf[32];
    size_t bi = 0;
    for (const char *s = t; ; s++) {
        if (*s == ':' || *s == '\0') {
            buf[bi] = '\0';
            total = total * 60 + strtod(buf, NULL);
            bi = 0;
            if (*s == '\0') return total;
        } else if (((*s >= '0' && *s <= '9') || *s == '.')
                   && bi < sizeof buf - 1) {
            buf[bi++] = *s;
        }
    }
}

@ {\bf Retrieving date, meet, and standard.}  The lightweight
\.{GetBestTimesForMember} feed this program originally used returned
only a stroke, distance, course, and formatted time --- no swim date,
meet name, or motivational standard.  Those three fields are, however,
reachable anonymously through the richer \.{POST /BestTimes} query, the
same call the data-hub front-end issues to render a swimmer's
``Best~Times'' page.  Given a |memberId|, a stroke abbreviation, and a
distance, \.{BestTimes} returns the swimmer's lifetime-best time in each
course (SCY and~LCM) for that stroke-and-distance pair, and each record
now carries |meetName|, |swimDate|, |eventCode|, |swimTime|, and
|timeStandard| --- the \.{B}, \.{BB}, \.{A}, \.{AA}, \.{AAA}, \.{AAAA},
or elite (\.{Nats}, \.{Trials}, \dots) level attained.  This is
requirement~\#1 and~\#2 of \.{requirements6.txt}.

@ Because \.{BestTimes} keys on a single stroke-and-distance pair, one
POST is issued per distinct pair among the requested events (about
twenty-two calls for the full thirty-one-event roster, since each call
delivers both courses).  Every parsed record is stored in a per-member
cache |g_cache|; each per-event query is then answered from that cache
without further network traffic.  The |date_min| and |date_max|
age-window parameters are retained for signature compatibility but are
not applied online.

@<Times fetch@>+=
typedef struct { char event[32]; TimeRow row; } CacheEntry;
static char       g_cache_member[64] = ""; /* memberId the cache holds */
static CacheEntry g_cache[NUM_EVENTS];     /* one best row per event   */
static int        g_cache_n = 0;           /* live entries in g_cache  */

@ |normalize_date| converts the API's \.{"Mon DD, YYYY"} date (e.g.\
\.{"Jan 19, 2019"}) to ISO~\.{YYYY-MM-DD}.  The ISO form sorts
lexically, contains no comma (so it needs no CSV quoting), and matches
the format the offline read path reconstructs with \.{to\_char}.  An
unrecognised input is copied through unchanged.

@<Times fetch@>+=
static void normalize_date(const char *in, char *out, size_t n)
{
    static const char *M = "JanFebMarAprMayJunJulAugSepOctNovDec";
    char mon[4]; int day = 0, yr = 0;
    if (sscanf(in, "%3s %d, %d", mon, &day, &yr) != 3) {
        snprintf(out, n, "%s", in);
        return;
    }
    const char *pos = strstr(M, mon);
    int m = pos ? (int)((pos - M) / 3) + 1 : 0;
    if (yr < 0 || yr > 9999) yr = 0;   /* bound so ISO output fits 16 bytes */
    if (m  < 0 || m  > 99)   m  = 0;
    if (day < 0 || day > 99) day = 0;
    snprintf(out, n, "%04d-%02d-%02d", yr, m, day);
}

@ |cache_add| appends one parsed \.{BestTimes} record to |g_cache|,
computing the numeric sort key from the formatted time and normalising
the date to ISO form.

@<Times fetch@>+=
static void cache_add(const char *event, const char *time,
                      const char *date, const char *standard,
                      const char *meet)
{
    if (g_cache_n >= NUM_EVENTS) return;
    CacheEntry *e = &g_cache[g_cache_n++];
    snprintf(e->event,        sizeof e->event,        "%s", event);
    e->row.sort_key = time_to_seconds(time);
    snprintf(e->row.time,     sizeof e->row.time,     "%s", time);
    normalize_date(date, e->row.date, sizeof e->row.date);
    snprintf(e->row.standard, sizeof e->row.standard, "%s", standard);
    snprintf(e->row.meet,     sizeof e->row.meet,     "%s", meet);
}

@ |fetch_pair| POSTs one \.{BestTimes} query for a stroke abbreviation
and distance and parses every returned record into the cache.

@<Times fetch@>+=
static void fetch_pair(const char *member_id, const char *stroke, long dist)
{
    char url[256], body[256];
    snprintf(url, sizeof url, "%s/BestTimes", TIMES_API);
    snprintf(body, sizeof body,
             "{\"memberId\":\"%s\",\"strokeAbbreviation\":\"%s\","
             "\"distance\":%ld}", member_id, stroke, dist);
    char *resp = http_request(url, body);
    if (!resp) return;
    @<Parse BestTimes records@>
    free(resp);
}

@ Within each record the fields appear in the fixed order |meetName|,
|eventCode|, |swimDate|, |swimTime|, |timeStandard|, so the scanner
reads them in that sequence, advancing its position pointer past each.
|timeStandard| may be JSON |null| (no standard earned); the scan then
leaves |std| empty.

@<Parse BestTimes records@>=
const char *p = resp;
char meet[256], event[32], date[16], stime[32], std[48];
while (scan_string("meetName", &p, meet, sizeof meet)) {
    if (!scan_string("eventCode", &p, event, sizeof event)) break;
    if (!scan_string("swimDate",  &p, date,  sizeof date))  break;
    if (!scan_string("swimTime",  &p, stime, sizeof stime)) break;
    std[0] = '\0';
    scan_string("timeStandard", &p, std, sizeof std);
    cache_add(event, stime, date, std, meet);
}

@ |build_member_cache| fills |g_cache| for |member_id| by issuing one
\.{BestTimes} POST per distinct stroke-and-distance pair drawn from the
effective event list (the \.{-e} selection when given, otherwise all
thirty-one |EVENTS|).  Pairs already fetched are skipped so each POST
runs at most once.

@<Times fetch@>+=
static void build_member_cache(const char *member_id)
{
    g_cache_n = 0;
    int use_e = (g_nevents > 0);
    int n = use_e ? g_nevents : NUM_EVENTS;
    char done[NUM_EVENTS][16]; int nd = 0;
    for (int i = 0; i < n; i++) {
        const char *code = use_e ? g_events[i] : EVENTS[i];
        long dist; char stroke[8], key[16];
        if (sscanf(code, "%ld %7s", &dist, stroke) != 2) continue;
        snprintf(key, sizeof key, "%s %ld", stroke, dist);
        @<Skip pair if already fetched@>
        fetch_pair(member_id, stroke, dist);
    }
    snprintf(g_cache_member, sizeof g_cache_member, "%s", member_id);
}

@ A linear scan of the |done| list suppresses a repeat POST for a
stroke-and-distance pair whose SCY and LCM events both appear in the
event list.

@<Skip pair if already fetched@>=
int seen = 0;
for (int j = 0; j < nd; j++)
    if (strcmp(done[j], key) == 0) { seen = 1; break; }
if (seen) continue;
if (nd < NUM_EVENTS) snprintf(done[nd++], sizeof done[0], "%s", key);

@ |fetch_times| reports |member_id|'s best time in |event_code|.  The
per-member cache is rebuilt whenever the requested member changes; the
matching row (if any) is then copied out and handed to the shared
sort/emit chunk.

@<Times fetch@>+=
static void fetch_times(const char *member_id, const char *event_code,
                        const char *swimmer_name, int opts,
                        const char *date_min, const char *date_max)
{
    (void)date_min; (void)date_max;
    if (strcmp(g_cache_member, member_id) != 0)
        build_member_cache(member_id);
    @<Select cached time for event@>
    @<Sort and emit rows@>
}

@ The cache holds at most one best row per event, so the selection is a
simple linear scan for the matching |event_code|.

@<Select cached time for event@>=
TimeRow rows[MAX_TIMES];
int nrows = 0;
for (int i = 0; i < g_cache_n && nrows < MAX_TIMES; i++)
    if (strcmp(g_cache[i].event, event_code) == 0)
        rows[nrows++] = g_cache[i].row;

@ The sort runs once and then up to three emitters are dispatched
according to the option mask: CSV to stdout, DB pipe write, or the
table to stdout.  CSV and DB emit can fire together; \.{store}
without \.{csv} writes silently to the database while still printing
the table.

@<Sort and emit rows@>=
insertion_sort(rows, nrows);
int lim = (opts & OPT_FASTEST) ? (nrows > 0 ? 1 : 0) : nrows;
if (opts & OPT_CSV)                  { @<Emit rows as CSV@>   }
if ((opts & OPT_STORE) && db_conn)   { @<Emit rows to DB@>    }
if (!(opts & OPT_CSV))               { @<Emit rows as table@> }

@ The CSV form on standard output is the same six-column layout
honoured by the existing CAST report pipeline.

@<Emit rows as CSV@>=
for (int i = 0; i < lim; i++)
    printf("\"%s\",\"%s\",\"%s\",\"%s\",\"%s\",\"%s\"\n",
           swimmer_name ? swimmer_name : "", event_code,
           rows[i].time, rows[i].date, rows[i].standard, rows[i].meet);

@ The DB form delegates each row to |db_insert_row|.  Per-row inserts
let \.{ON CONFLICT DO NOTHING} swallow duplicates one at a time
without aborting the surrounding work --- the bulk \.{COPY} path
would have rolled back the whole batch on the first collision.

@<Emit rows to DB@>=
for (int i = 0; i < lim; i++)
    db_insert_row(swimmer_name ? swimmer_name : "",
                  event_code, &rows[i]);

@ The table form is the human-readable per-event block printed when
\.{csv} is not requested.

@<Emit rows as table@>=
printf("%s --- %s:\n", event_code,
       (opts & OPT_FASTEST) ? "fastest time" : "all times (fastest first)");
printf("%-12s  %-10s  %-13s  %s\n", "Time", "Date", "Standard", "Meet");
printf("%-12s  %-10s  %-13s  %s\n",
       "------------", "----------", "-------------", "----");
for (int i = 0; i < lim; i++)
    printf("%-12s  %-10s  %-13s  %s\n",
           rows[i].time, rows[i].date, rows[i].standard, rows[i].meet);
if (nrows == 0)
    printf("(no times found)\n");
putchar('\n');

@* Offline fetch.

@ |offline_fetch| is the read counterpart to the insert path: it
issues a parameterised \.{SELECT} via \.{libpq} on the shared
|db_conn| and feeds each tuple into the same |TimeRow| array
consumed by the shared sort/emit chunk.  No network is touched and
no child process is spawned.  The function takes a |Swimmer|
pointer so it can use both |match_substr| (for an \.{ILIKE} clause
that maps the user keyword to whichever full name the database
happens to hold) and the optional age window
(|date_min|, |date_max|).

@<Offline fetch@>=
@<Define offline\_fetch@>

@ The fetch function is decomposed into three sub-chunks so each
stays inside the twenty-four line limit.

@<Define offline\_fetch@>=
static void offline_fetch(const Swimmer *sw, const char *event_code, int opts)
{
    @<Build offline query params@>
    @<Read offline rows from libpq@>
    @<Sort and emit rows@>
}

@ The query uses two positional parameters: the \.{ILIKE} pattern
(\.{\%match\_substr\%}) and the event code.  libpq quotes them
safely so no shell-quoting hazards apply.

@<Build offline query params@>=
char like_pat[256];
snprintf(like_pat, sizeof like_pat, "%%%s%%", sw->match_substr);
const char *params[2] = { like_pat, event_code };
const char *q =
    "SELECT swimmer, swim_time, "
    "to_char(swim_date,'YYYY-MM-DD'), "
    "standard, meet, sort_key FROM swim_times "
    "WHERE swimmer ILIKE $1 AND event = $2 "
    "ORDER BY sort_key";

@ The query is executed, the result is iterated, and each tuple is
copied into a |TimeRow|.  The age window is honoured here so that an
offline query that ignores the filter (e.g.\ a wider DB range) still
produces age-appropriate output.

@<Read offline rows from libpq@>=
char swimmer_buf[256] = "";
const char *swimmer_name = swimmer_buf;
TimeRow rows[MAX_TIMES];
int nrows = 0;

if (!db_conn) {
    fputs("Error: no DB connection for offline read\n", stderr);
    return;
}
PGresult *res = PQexecParams(db_conn, q, 2, NULL, params,
                             NULL, NULL, 0);
if (PQresultStatus(res) != PGRES_TUPLES_OK) {
    fprintf(stderr, "Error: offline query failed: %s",
        PQerrorMessage(db_conn));
    PQclear(res);
    return;
}
int total = PQntuples(res);
for (int i = 0; i < total && nrows < MAX_TIMES; i++) {
    @<Copy one libpq row@>
}
PQclear(res);

@ Each tuple carries six columns matching the \.{SELECT} list:
swimmer name, time, date, standard, meet, sort key.  Rows that
fall outside the swimmer's optional age window are skipped without
incrementing |nrows|.

@<Copy one libpq row@>=
const char *f0 = PQgetvalue(res, i, 0);
const char *f1 = PQgetvalue(res, i, 1);
const char *f2 = PQgetvalue(res, i, 2);
const char *f3 = PQgetvalue(res, i, 3);
const char *f4 = PQgetvalue(res, i, 4);
const char *f5 = PQgetvalue(res, i, 5);
if (sw->date_min && strcmp(f2, sw->date_min) < 0) continue;
if (sw->date_max && strcmp(f2, sw->date_max) > 0) continue;
if (!*swimmer_buf) {
    strncpy(swimmer_buf, f0, sizeof swimmer_buf - 1);
    swimmer_buf[sizeof swimmer_buf - 1] = '\0';
}
strncpy(rows[nrows].time, f1, sizeof rows[nrows].time - 1);
rows[nrows].time[sizeof rows[nrows].time - 1] = '\0';
strncpy(rows[nrows].date, f2, sizeof rows[nrows].date - 1);
rows[nrows].date[sizeof rows[nrows].date - 1] = '\0';
strncpy(rows[nrows].standard, f3, sizeof rows[nrows].standard - 1);
rows[nrows].standard[sizeof rows[nrows].standard - 1] = '\0';
strncpy(rows[nrows].meet, f4, sizeof rows[nrows].meet - 1);
rows[nrows].meet[sizeof rows[nrows].meet - 1] = '\0';
rows[nrows].sort_key = strtod(f5, NULL);
nrows++;

@* Main program.

@ We define a small |Swimmer| record to hold the person-search
parameters for each swimmer.  Each entry supplies a unique |id| string
(the token the user passes to \.{-o} to select her), a |search_query|
string sent to the database (ideally distinctive enough to return a
small set), and a |match_substr| (lower-cased) used to identify the
correct row among the results.  The optional |date_min| and |date_max| fields restrict
output to swims whose date falls in $[\hbox{|date_min|}, \hbox{|date_max|}]$
(inclusive, ISO~\.{YYYY-MM-DD}).  These are used to express age-group
windows---for example Katie Ledecky's 9- and 10-year-old swims fall
between her ninth and eleventh birthdays.
Kalea's entry searches ``Benavente'' because the simple two-word query
``Kalea Benavente'' returns no results; the API requires an exact substring
match against the registered name ``Kalea Rose Benavente''.
Kenneth's entry uses ``kenneth ray'' and Keith's uses ``keith santiago''
to avoid false matches on the common surname ``Evans''.
Katie Ledecky was born 17~March~1997, so the window
\.{2006-03-17} through \.{2008-03-16} captures every swim from her
ninth birthday up to (but not including) her eleventh.  The same
construction yields \.{2008-03-17} through \.{2010-03-16} for the
11- and 12-year-old window (\.{ledecky12}) and \.{2010-03-17}
through \.{2012-03-16} for the 13- and 14-year-old window
(\.{ledecky14}).

@<Main function@>=
static const Swimmer SWIMMERS[] = {
  { "stella",     "Julianna Evans",  "stella",         NULL, NULL },
  { "kalea",      "Benavente",       "kalea",          NULL, NULL },
  { "kenny",      "Ray Evans",       "kenneth ray",    NULL, NULL },
  { "keith",      "Santiago Evans",  "keith santiago", NULL, NULL },
  { "ledecky10",  "Ledecky",         "katie",          "2006-03-17", "2008-03-16" },
  { "ledecky12",  "Ledecky",         "katie",          "2008-03-17", "2010-03-16" },
  { "ledecky14",  "Ledecky",         "katie",          "2010-03-17", "2012-03-16" },
  /* Roster added per requirements (all College Area Swim Team, LSC SI).  */
  /* The query is "First Last"; the match token is a lower-case substring */
  /* that uniquely picks the CAST member among the search results ---     */
  /* chosen to sidestep nicknames and same-name swimmers in other LSCs.   */
  { "bothwell-emma",        "Emma Bothwell",        "emma",       NULL, NULL },
  { "coombs-wally",         "Wally Coombs",         "wally",      NULL, NULL },
  { "cruz-eva",             "Eva Cruz",             "cruz rae",   NULL, NULL },
  { "darrow-zoe",           "Zoe Darrow",           "zoe",        NULL, NULL },
  { "doan-eva",             "Eva Doan",             "eva doan",   NULL, NULL },
  { "ellis-nova",           "Nova Ellis",           "nova",       NULL, NULL },
  /* Evans, Stella J is the same swimmer as ``stella'' above.            */
  { "fedyshyn-liliya",      "Liliya Fedyshyn",      "liliya",     NULL, NULL },
  { "glass-layla",          "Layla Glass",          "layla",      NULL, NULL },
  { "glass-logan",          "Logan Glass",          "wiley",      NULL, NULL },
  { "gosser-hannah",        "Hannah Gosser",        "gosser",     NULL, NULL },
  { "huynh-diamond",        "Diamond Huynh",        "diamond",    NULL, NULL },
  { "knuth-hannah",         "Hannah Knuth",         "knuth",      NULL, NULL },
  { "lefebvre-bailey-cleo", "Cleo Lefebvre-Bailey", "cleo",       NULL, NULL },
  { "mendez-giavanna",      "Giavanna Mendez",      "mendez",     NULL, NULL },
  { "mulvaney-sofia",       "Sofia Mulvaney",       "sofia",      NULL, NULL },
  { "shay-naia",            "Naia Shay",            "naia",       NULL, NULL },
  { "simmons-briar",        "Briar Simmons",        "briar",      NULL, NULL },
  { "simmons-presley",      "Presley Simmons",      "aspen",      NULL, NULL },
  { "soto-lucas",           "Lucas Soto",           "erick",      NULL, NULL },
  { "soto-vivienne",        "Vivienne Soto",        "vivi",       NULL, NULL },
  { "wittmershaus-addison", "Addison Wittmershaus", "addison",    NULL, NULL },
  { "zahner-elsie",         "Elsie Zahner",         "elsie",      NULL, NULL }
};
#define NUM_SWIMMERS ((int)(sizeof SWIMMERS / sizeof SWIMMERS[0]))

@ |parse_opts_str| tokenises a comma-separated option string (the
argument to \.{-o}) and sets bits in |g_opts|.  Unknown tokens are
silently ignored so that future options can be added without breaking
existing invocations.

@<Main function@>+=
static void parse_opts_str(const char *s)
{
    /* Work on a writable copy so strtok can insert NUL bytes. */
    char *buf = strdup(s);
    if (!buf) return;
    char *tok = strtok(buf, ",");
    while (tok) {
        if      (strcmp(tok, "fastest")   == 0) g_opts |= OPT_FASTEST;
        else if (strcmp(tok, "csv")       == 0) g_opts |= OPT_CSV;
        else if (strcmp(tok, "store")     == 0) g_opts |= OPT_STORE;
        else if (strcmp(tok, "offline")   == 0) g_opts |= OPT_OFFLINE;
        else if (g_nsel < MAX_SEL)              g_sel[g_nsel++] = strdup(tok);
        tok = strtok(NULL, ",");
    }
    free(buf);
}

@ |parse_events_str| tokenises a comma-separated event-code string (the
argument to \.{-e}) and appends each code to |g_events|.  Codes that would
overflow the |NUM_EVENTS|-entry array are silently dropped.  The flag may
be supplied multiple times; each invocation extends the list.

@<Main function@>+=
static void parse_events_str(const char *s)
{
    char *buf = strdup(s);
    if (!buf) return;
    char *tok = strtok(buf, ",");
    while (tok && g_nevents < NUM_EVENTS) {
        /* Trim leading spaces left by comma-split with spaces around commas. */
        while (*tok == ' ') tok++;
        strncpy(g_events[g_nevents], tok, sizeof g_events[0] - 1);
        g_events[g_nevents][sizeof g_events[0] - 1] = '\0';
        g_nevents++;
        tok = strtok(NULL, ",");
    }
    free(buf);
}

@ |print_usage| writes the full usage message to standard error.
It is split into two sub-modules: one for the options section and one
for the examples section.

@<Main function@>+=
static void print_usage(const char *prog)
{
    @<Print usage options@>
    @<Print usage examples@>
}

@ The options section is split into three sub-modules so each
fprintf stays inside the twenty-four line limit.

@<Print usage options@>=
@<Print usage flags@>
@<Print usage swimmers@>
@<Print usage event codes@>

@ The \.{-o} keyword list.  A token is either one of the four behaviour
keywords below or a swimmer {\it id\/}; behaviour keywords and ids may be
freely mixed.  With no swimmer id every swimmer on the roster is
processed.

@<Print usage flags@>=
fprintf(stderr,
    "Usage: %s -o token[,token...] [-e event[,event...]]\n\n"
    "  -o token,...    comma-separated; each token is a behaviour keyword\n"
    "                  or a swimmer id.  Behaviour keywords:\n"
    "       fastest     print only the single fastest time per event\n"
    "       csv         emit CSV output (header + one line per time)\n"
    "       store       persist each row to Postgres swim-times via libpq\n"
    "       offline     read times from the Postgres swim-times DB\n"
    "                   instead of querying USA Swimming over the network\n"
    "  Any other token selects a swimmer by id; with none, all are shown.\n\n",
    prog);

@ The swimmer ids are listed straight from the |SWIMMERS| roster so the
help text can never drift out of sync with the table.

@<Print usage swimmers@>=
fprintf(stderr, "  swimmer ids (%d):\n", NUM_SWIMMERS);
for (int i = 0; i < NUM_SWIMMERS; i++)
    fprintf(stderr, "%s%-22s%s",
            (i % 3 == 0) ? "       " : "",
            SWIMMERS[i].id,
            (i % 3 == 2 || i == NUM_SWIMMERS - 1) ? "\n" : " ");
fputc('\n', stderr);

@ The \.{-e} event-code menu.

@<Print usage event codes@>=
fprintf(stderr,
    "  -e event,...    restrict output to one or more event codes;\n"
    "                  comma-separated, or repeat -e for each event.\n"
    "       SCY codes:  50 FR SCY, 100 FR SCY, 200 FR SCY, 500 FR SCY,\n"
    "                   1000 FR SCY, 1650 FR SCY,\n"
    "                   50 FL SCY, 100 FL SCY, 50 BK SCY, 100 BK SCY,\n"
    "                   50 BR SCY, 100 BR SCY, 100 IM SCY, 200 IM SCY\n"
    "       LCM codes:  50 FR LCM, 100 FR LCM, 200 FR LCM, 400 FR LCM,\n"
    "                   800 FR LCM, 1500 FR LCM,\n"
    "                   50 FL LCM, 100 FL LCM, 200 FL LCM,\n"
    "                   50 BK LCM, 100 BK LCM, 200 BK LCM,\n"
    "                   50 BR LCM, 100 BR LCM, 200 BR LCM,\n"
    "                   200 IM LCM, 400 IM LCM\n\n");

@ The examples section illustrates common invocations.

@<Print usage examples@>=
fprintf(stderr,
    "Examples:\n"
    "  %s -o stella,fastest\n"
    "  %s -o kalea,csv\n"
    "  %s -o kenny -e \"100 FR SCY\"\n"
    "  %s -o keith -e \"100 FR SCY,50 FL SCY\"\n"
    "  %s -o stella -e \"100 FR SCY\" -e \"50 FL SCY\"\n"
    "  %s -o stella,csv,store        # fetch + print + persist to DB\n"
    "  %s -o kalea,offline           # read from DB, no network\n"
    "  %s -o ledecky10,fastest       # Katie Ledecky as a 9-10 yr old\n",
    prog, prog, prog, prog, prog, prog, prog, prog);

@ We initialise the global \.{libcurl} state, parse the optional
\.{-o} and \.{-e} flags, then for each swimmer (subject to the selected
swimmer ids in |g_sel|) resolve her |memberId| and iterate over events.  If one or more
\.{-e} codes were given only those events are fetched; otherwise all thirty-one
are processed.  In CSV mode a single header line is printed before the first
data row.  If no options at all are supplied, the usage message is printed
and the program exits with status~1.  The function body is split into three
sub-modules.

@<Main function@>+=
int main(int argc, char *argv[])
{
    @<Parse command-line options@>
    @<Check for empty invocation@>
    @<Fetch and print swimmer times@>
}

@ The option-parsing loop processes \.{-o} and \.{-e} flags via |getopt|.

@<Parse command-line options@>=
int ch;
while ((ch = getopt(argc, argv, "o:e:")) != -1) {
    switch (ch) {
    case 'o':
        parse_opts_str(optarg);
        break;
    case 'e':
        parse_events_str(optarg);
        break;
    default:
        print_usage(argv[0]);
        return 2;
    }
}

@ If no options were supplied the usage message is printed and the program
exits.  Otherwise global curl state is initialised (skipped under
\.{offline}, where no HTTP is performed), the CSV header is emitted if
needed, and the DB pipe is opened if \.{store} was requested.

@<Check for empty invocation@>=
if (g_opts == 0 && g_nevents == 0 && g_nsel == 0) {
    print_usage(argv[0]);
    return 1;
}

if (!(g_opts & OPT_OFFLINE))
    curl_global_init(CURL_GLOBAL_DEFAULT);

if (g_opts & OPT_CSV)
    printf("\"Swimmer\",\"Event\",\"Time\",\"Date\",\"Standard\",\"Meet\"\n");

if (g_opts & (OPT_STORE | OPT_OFFLINE)) {
    int ok = db_open();
    if (!ok && (g_opts & OPT_OFFLINE)) {
        fputs("Error: offline mode requires a DB connection\n", stderr);
        return 1;
    }
}

@ Each swimmer is visited in turn.  The swimmer-filter mask is applied
before the expensive |memberId| lookup.  The DB pipe (if any) is
flushed and closed before \.{libcurl} is torn down.

@<Fetch and print swimmer times@>=
for (int s = 0; s < NUM_SWIMMERS; s++) {
    @<Process one swimmer@>
}

db_close();
if (!(g_opts & OPT_OFFLINE)) curl_global_cleanup();
return 0;

@ One swimmer is resolved and all requested events are fetched.
Under \.{offline} the network |memberId| lookup is bypassed and the
swimmer's display name is taken from the database in |offline_fetch|.
The online branch is split into its own sub-chunk.

@<Process one swimmer@>=
if (g_nsel > 0) {
    int selected = 0;
    for (int k = 0; k < g_nsel; k++)
        if (strcmp(g_sel[k], SWIMMERS[s].id) == 0) { selected = 1; break; }
    if (!selected) continue;
}

if (g_opts & OPT_OFFLINE) {
    @<Fetch events offline@>
    continue;
}

@<Online swimmer dispatch@>

@ The online path resolves a |memberId| and dispatches the per-event
fetcher.  A failed lookup is fatal; the DB pipe is closed and curl is
torn down before exit.

@<Online swimmer dispatch@>=
const char *name = NULL;
char *key = lookup_member_id(SWIMMERS[s].search_query,
                             SWIMMERS[s].match_substr,
                             &name);
if (!key) {
    db_close();
    curl_global_cleanup();
    return 1;
}

if (!(g_opts & OPT_CSV))
    printf("Swimmer: %s  (MemberId: %s)\n\n",
           name ? name : "(unknown)", key);

@<Fetch events for swimmer@>

free(key);
free((void *)name);
if (!(g_opts & OPT_CSV))
    putchar('\n');

@ Either the user-requested events or all thirty-one default events are
fetched online.  The optional age window from the |Swimmer| record is
forwarded to |fetch_times|.

@<Fetch events for swimmer@>=
if (g_nevents > 0) {
    for (int i = 0; i < g_nevents; i++)
        fetch_times(key, g_events[i], name, g_opts,
                    SWIMMERS[s].date_min, SWIMMERS[s].date_max);
} else {
    for (int i = 0; i < NUM_EVENTS; i++)
        fetch_times(key, EVENTS[i], name, g_opts,
                    SWIMMERS[s].date_min, SWIMMERS[s].date_max);
}

@ The offline counterpart calls |offline_fetch| once per event.  No
HTTP request is performed, no |memberId| is resolved, and the DB
pipe is irrelevant (\.{store} composes only with online runs).

@<Fetch events offline@>=
if (g_nevents > 0) {
    for (int i = 0; i < g_nevents; i++)
        offline_fetch(&SWIMMERS[s], g_events[i], g_opts);
} else {
    for (int i = 0; i < NUM_EVENTS; i++)
        offline_fetch(&SWIMMERS[s], EVENTS[i], g_opts);
}
if (!(g_opts & OPT_CSV)) putchar('\n');

@* Glossary.

The following terms and interfaces appear throughout this program.

@
\def\gitem#1{\medskip\noindent{\bf #1.}\enspace\ignorespaces}
\def\sig#1{\par\noindent\quad{\tt #1}\par\noindent}

\gitem{USA Swimming times API}
The first-party REST service at \.{times-api.usaswimming.org} that
backs the public data hub at \.{data.usaswimming.org}.  It replaced the
Sisense JAQL analytics API this program originally used (now
decommissioned for public callers).  Requests are ordinary HTTP
\.{GET}/\.{POST} calls returning JSON; the OpenAPI description is
published at \.{.../swagger/v1/swagger.json}.

\gitem{Anonymous data-hub authentication}
The times API uses no bearer token for public data.  Every request
instead carries three headers: \.{Usas-Sub-Id} (the caller's subject,
or the literal \.{Anonymous} when not signed in), \.{AppName: DataHub},
and a \.{Device-Id}.  The server validates the {\it format\/} of the
\.{Device-Id}---base64 of \.{"<platform> - <vendor> - <fingerprint> -
<millis>"} with the first five base64 characters repeated after the
fifteenth---so |device_id| mints a conforming value at run time.

\gitem{memberId}
The service's identifier for a swimmer, an alphanumeric token such as
\.{6CD35348E5824C} (it replaces the old numeric \.{PersonKey}).

@ {\bf USA Swimming REST API Calls.}
Both endpoints live under
\.{https://times-api.usaswimming.org/swims/TimesSearch} and carry
\.{Content-Type: application/json} plus the anonymous auth headers
above.

\medskip
\item{$\bullet$} {\bf Member search.}
  \.{POST /GetMembersForFilters} with body
  \.{\{"name":"<query>"\}}.  Returns a JSON array of member objects,
  each with (among others) \.{memberId}, \.{fullName}, \.{clubName},
  and \.{lscCode}.  This program scans the array for the first member
  whose lower-cased \.{fullName} contains the match substring and keeps
  that record's \.{memberId}.

\item{$\bullet$} {\bf Best-times fetch.}
  \.{POST /BestTimes} with body \.{\{"memberId":"<id>",
  "strokeAbbreviation":"<abbr>","distance":<n>\}}.  Returns a JSON array
  with one object per course (SCY and~LCM) for that stroke-and-distance
  pair, each carrying \.{eventCode}, \.{swimTime} (formatted),
  \.{swimDate} (\.{"Mon DD, YYYY"}), \.{meetName}, and \.{timeStandard}
  (\.{B}, \.{BB}, \.{A}, \.{AA}, \.{AAA}, \.{AAAA}, or an elite label;
  JSON \.{null} when none was earned).  This is the query the data-hub
  ``Best~Times'' page issues, and unlike the older
  \.{GetBestTimesForMember} GET it exposes date, meet, and standard to
  anonymous callers.  One POST is issued per distinct stroke-and-distance
  pair.  The still-richer per-swim endpoints
  (\.{GetAllTimesForFilters}, \.{GetSwimmerMeets}) require a signed-in
  subject and return \.{403} otherwise.

@ {\bf libcurl API Calls.}
This program uses the libcurl ``easy'' interface for synchronous HTTP.
All functions return a |CURLcode| (zero = \.{CURLE\_OK}) except where
noted.

\medskip
\item{$\bullet$} {\tt curl\_global\_init(flags)}.
  \par\noindent Parameter: {\tt flags} ({\tt long}) ---
  a bitmask of subsystems to initialise.
  This program passes \.{CURL\_GLOBAL\_DEFAULT}, which enables SSL
  and the Windows socket layer on that platform.
  Must be called once before any other libcurl function.
  Returns a {\tt CURLcode}; this program ignores the return value
  because failure is treated as fatal by the subsequent easy calls.

\item{$\bullet$} {\tt curl\_global\_cleanup(void)}.
  Releases all resources allocated by |curl_global_init|.
  Must be called once after all easy handles have been cleaned up.
  Returns nothing.

\item{$\bullet$} {\tt curl\_easy\_init(void)}.
  Allocates and returns a new easy handle (a \.{CURL *}).
  Returns \.{NULL} on failure.
  Each call to |http_request| creates its own handle and destroys it
  before returning, so handles are never shared between requests.

\item{$\bullet$} {\tt curl\_easy\_setopt(handle, option, value)}.
  \par\noindent Parameters:
  \itemitem{--} {\tt handle} ({\tt CURL *}): the easy handle.
  \itemitem{--} {\tt option} ({\tt CURLoption}): a constant selecting
    the behaviour to configure.  Options used here:
    \itemitem{} \.{CURLOPT\_URL} ({\tt char *}) --- the request URL.
    \itemitem{} \.{CURLOPT\_HTTPHEADER} ({\tt struct curl\_slist *}) ---
      linked list of extra HTTP headers (\.{Content-Type} and the
      anonymous \.{Usas-Sub-Id}, \.{AppName}, \.{Device-Id} headers).
    \itemitem{} \.{CURLOPT\_POSTFIELDS} ({\tt char *}) ---
      the POST body; set only when a body is supplied, which also
      switches the method to POST (best-times fetches are plain GETs).
    \itemitem{} \.{CURLOPT\_WRITEFUNCTION} (function pointer) ---
      callback invoked for each response chunk; signature
      {\tt size\_t cb(void*,size\_t,size\_t,void*)}.
    \itemitem{} \.{CURLOPT\_WRITEDATA} ({\tt void *}) ---
      the user-data pointer passed as the fourth argument to the
      write callback; here a pointer to the |Buffer| accumulator.
  \itemitem{--} {\tt value}: type depends on {\tt option} (see above).

\item{$\bullet$} {\tt curl\_easy\_perform(handle)}.
  \par\noindent Parameter: {\tt handle} ({\tt CURL *}).
  Executes the configured request synchronously, invoking the write
  callback for each received chunk.
  Returns \.{CURLE\_OK} on success or a non-zero error code; on failure
  |http_request| frees the partial buffer and returns \.{NULL}.

\item{$\bullet$} {\tt curl\_easy\_cleanup(handle)}.
  \par\noindent Parameter: {\tt handle} ({\tt CURL *}).
  Releases all resources associated with the handle.
  The handle must not be used after this call.

\item{$\bullet$} {\tt curl\_slist\_append(list, string)}.
  \par\noindent Parameters:
  \itemitem{--} {\tt list} ({\tt struct curl\_slist *}):
    existing list head, or \.{NULL} to start a new list.
  \itemitem{--} {\tt string} ({\tt const char *}): the string to append.
  Returns the new list head, or \.{NULL} on allocation failure.
  Used to build the two-header list
  (\.{Content-Type} then \.{Authorization}).

\item{$\bullet$} {\tt curl\_slist\_free\_all(list)}.
  \par\noindent Parameter: {\tt list} ({\tt struct curl\_slist *}).
  Frees every node in the linked list.
  Called immediately after |curl_easy_perform| so the headers are
  released before the handle.

@ {\bf POSIX System Calls and Library Functions.}
The following identifiers from the POSIX.1-2008 standard are used
directly in this program.  Each entry gives the C~signature, a
description of each parameter, and a note on how the program uses it.

\medskip
\item{$\bullet$} {\tt int fprintf(FILE *stream, const char *fmt, ...)}.
  \par\noindent Parameters:
  \itemitem{--} {\tt stream}: destination file (\.{stderr} here).
  \itemitem{--} {\tt fmt}: printf-style format string.
  \itemitem{--} {\tt ...}: values substituted into {\tt fmt}.
  Writes formatted output to {\tt stream}; returns the character count
  or a negative value on error.
  Used to report lookup and HTTP failures to standard error.

\item{$\bullet$} {\tt int fputs(const char *s, FILE *stream)}.
  \par\noindent Parameters:
  \itemitem{--} {\tt s}: null-terminated string to write.
  \itemitem{--} {\tt stream}: destination file (\.{stderr} here).
  Writes {\tt s} without a trailing newline; returns non-negative on
  success or \.{EOF} on error.
  Used for fixed error messages where no formatting is needed.

\item{$\bullet$} {\tt void free(void *ptr)}.
  \par\noindent Parameter:
  \itemitem{--} {\tt ptr}: pointer to a heap block, or \.{NULL}
    (in which case nothing happens).
  Releases the block back to the heap.
  Called on every heap string (response buffers, duplicated names and
  keys) when they are no longer needed.

\item{$\bullet$} {\tt void *memcpy(void *dst, const void *src, size\_t n)}.
  \par\noindent Parameters:
  \itemitem{--} {\tt dst}: destination address.
  \itemitem{--} {\tt src}: source address.
  \itemitem{--} {\tt n}: number of bytes to copy.
  Copies exactly {\tt n} bytes from {\tt src} to {\tt dst};
  regions must not overlap.
  Returns {\tt dst}.
  Used in |write_cb| to append each network chunk to the buffer,
  and in |scan_string| to copy a JSON string value.

\item{$\bullet$} {\tt int printf(const char *fmt, ...)}.
  \par\noindent Parameters:
  \itemitem{--} {\tt fmt}: printf-style format string.
  \itemitem{--} {\tt ...}: values substituted into {\tt fmt}.
  Writes formatted output to standard output; returns the character
  count or a negative value on error.
  Used for all swimmer and time-table output.

\item{$\bullet$} {\tt int putchar(int c)}.
  \par\noindent Parameter:
  \itemitem{--} {\tt c}: character value (as {\tt unsigned char} cast
    to {\tt int}).
  Writes one character to standard output; returns the character
  written, or \.{EOF} on error.
  Used to emit a blank line (\.{'\char`\\n'}) after each event section.

\item{$\bullet$} {\tt void *realloc(void *ptr, size\_t size)}.
  \par\noindent Parameters:
  \itemitem{--} {\tt ptr}: existing heap block, or \.{NULL}.
  \itemitem{--} {\tt size}: new size in bytes.
  Returns a pointer to the resized block (possibly moved), or \.{NULL}
  if allocation fails (the original block is unchanged on failure).
  When {\tt ptr} is \.{NULL} the call is equivalent to {\tt malloc}.
  Used in |write_cb| to grow the response buffer incrementally as
  libcurl delivers each chunk.

\item{$\bullet$} {\tt int snprintf(char *buf, size\_t n, const char *fmt, ...)}.
  \par\noindent Parameters:
  \itemitem{--} {\tt buf}: destination character array.
  \itemitem{--} {\tt n}: maximum bytes to write, including the null terminator.
  \itemitem{--} {\tt fmt}: printf-style format string.
  \itemitem{--} {\tt ...}: values substituted into {\tt fmt}.
  Writes at most {\tt n}$-1$ formatted characters to {\tt buf} and
  always null-terminates.  Returns the number of characters that would
  have been written had the buffer been unlimited (so a return value
  $\ge${\tt n} signals truncation).
  Used to assemble URL strings, JSON bodies, and the bearer-token header.

\item{$\bullet$} {\tt char *strchr(const char *s, int c)}.
  \par\noindent Parameters:
  \itemitem{--} {\tt s}: string to search.
  \itemitem{--} {\tt c}: character to find (compared as {\tt unsigned char}).
  Returns a pointer to the first occurrence of {\tt c} in {\tt s},
  including the terminator if {\tt c} is \.{'\char`\\0'}, or \.{NULL}.
  Used in |scan_string| to find the closing double-quote of a JSON
  string value.

\item{$\bullet$} {\tt char *strdup(const char *s)}.
  \par\noindent Parameter:
  \itemitem{--} {\tt s}: null-terminated string to duplicate.
  Allocates a new heap block of {\tt strlen(s)+1} bytes, copies
  {\tt s} into it, and returns the pointer; returns \.{NULL} on failure.
  Used in |lookup_member_id| to persist the swimmer's full name and
  memberId string across the lifetime of a query.

\item{$\bullet$} {\tt size\_t strlen(const char *s)}.
  \par\noindent Parameter:
  \itemitem{--} {\tt s}: null-terminated string.
  Returns the number of bytes before the null terminator.
  Used to compute loop bounds when lower-casing names and to advance
  past a search needle in |scan_string|.

\item{$\bullet$} {\tt char *strncpy(char *dst, const char *src, size\_t n)}.
  \par\noindent Parameters:
  \itemitem{--} {\tt dst}: destination array (at least {\tt n} bytes).
  \itemitem{--} {\tt src}: source string.
  \itemitem{--} {\tt n}: maximum bytes to copy.
  Copies up to {\tt n} bytes; if {\tt src} is shorter than {\tt n},
  the remainder of {\tt dst} is zero-filled.  If {\tt src} is at least
  {\tt n} bytes long, {\tt dst} will {\it not\/} be null-terminated.
  Returns {\tt dst}.
  This program always writes {\tt dst[sizeof dst - 1] = '\char`\\0'}
  after the call to guarantee termination.
  Used to copy the swimmer name and requested event codes; fixed
  {\tt TimeRow} fields are filled with |snprintf| instead.

\item{$\bullet$} {\tt char *strstr(const char *hay, const char *needle)}.
  \par\noindent Parameters:
  \itemitem{--} {\tt hay}: string to search within.
  \itemitem{--} {\tt needle}: substring to search for.
  Returns a pointer to the first occurrence of {\tt needle} in
  {\tt hay}, or \.{NULL} if not found.
  The workhorse of the JSON scanner: used to locate key names
  (\.{"memberId"}, \.{"fullName"}, \.{"swimTime"}, \dots) and to
  advance through the raw REST response text.

\item{$\bullet$} {\tt double strtod(const char *s, char **endptr)}.
  \par\noindent Parameters:
  \itemitem{--} {\tt s}: string containing a floating-point number.
  \itemitem{--} {\tt endptr}: if non-\.{NULL}, receives a pointer to the
    first character not consumed by the conversion.
  Returns the parsed {\tt double}; sets {\tt *endptr} past the
  converted text.
  Used by |time_to_seconds| to convert each colon-separated group of a
  formatted time (e.g.\ \.{"1:40.36"}) to a {\tt double} sort key.

\item{$\bullet$} {\tt int sscanf(const char *s, const char *fmt, ...)}.
  \par\noindent Parameters:
  \itemitem{--} {\tt s}: input string to parse.
  \itemitem{--} {\tt fmt}: scanf-style conversion string.
  \itemitem{--} {\tt ...}: pointers to receive the converted values.
  Reads formatted input from {\tt s}; returns the number of input items
  successfully matched and assigned (which may be fewer than requested,
  or \.{EOF} on failure).  Used by |normalize_date| to split
  \.{"Mon DD, YYYY"} into a month abbreviation, day, and year, and by
  |build_member_cache| to split an event code such as \.{"100 FR SCY"}
  into its numeric distance and stroke abbreviation.

@* Index.
