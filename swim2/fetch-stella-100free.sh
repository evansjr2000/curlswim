#!/usr/bin/env bash
# Fetches Stella Julianna Evans' 100 Freestyle SCY times from the USA Swimming data hub.
# Requires: curl, jq

set -euo pipefail

SISENSE_TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyIjoiNjY0YmE2NmE5M2ZiYTUwMDM4NWIyMWQwIiwiYXBpU2VjcmV0IjoiNDQ0YTE3NWQtM2I1OC03NDhhLTVlMGEtYTVhZDE2MmRmODJlIiwiYWxsb3dlZFRlbmFudHMiOlsiNjRhYzE5ZTEwZTkxNzgwMDFiYzM5YmVhIl0sInRlbmFudElkIjoiNjRhYzE5ZTEwZTkxNzgwMDFiYzM5YmVhIn0.izSIvaD2udKTs3QRngla1Aw23kZVyoq7Xh23AbPUw1M"
SISENSE_API="https://usaswimming.sisense.com/api/datasources"

# Step 1: Look up Stella Julianna Evans' PersonKey from the Public Person Search dataset.
PERSON_RESPONSE=$(curl -s -X POST \
  "${SISENSE_API}/aPublicIAAaPersonIAAaSearch/jaql" \
  -H "Authorization: Bearer ${SISENSE_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "datasource": {
      "title": "Public Person Search",
      "fullname": "LocalHost/Public Person Search"
    },
    "metadata": [
      {
        "jaql": {
          "table": "Persons", "column": "FullName", "dim": "[Persons.FullName]",
          "datatype": "text", "title": "Name",
          "filter": {"contains": "Julianna Evans"}
        }
      },
      {
        "jaql": {
          "table": "Persons", "column": "PersonKey", "dim": "[Persons.PersonKey]",
          "datatype": "numeric", "title": "PersonKey"
        }
      },
      {
        "jaql": {
          "table": "Persons", "column": "ClubName", "dim": "[Persons.ClubName]",
          "datatype": "text", "title": "Club"
        }
      }
    ],
    "count": 10,
    "offset": 0
  }')

PERSON_KEY=$(echo "${PERSON_RESPONSE}" | jq -r '
  .values[]
  | select(.[0].text | ascii_downcase | contains("stella"))
  | .[1].data' | head -1)

if [[ -z "${PERSON_KEY}" ]]; then
  echo "Error: could not find Stella Julianna Evans in the database." >&2
  exit 1
fi

PERSON_NAME=$(echo "${PERSON_RESPONSE}" | jq -r '
  .values[]
  | select(.[0].text | ascii_downcase | contains("stella"))
  | .[0].text' | head -1)

echo "Swimmer: ${PERSON_NAME}  (PersonKey: ${PERSON_KEY})"
echo ""

# Step 2: Fetch her 100 Freestyle SCY times from the USA Swimming Times Elasticube.
TIMES_RESPONSE=$(curl -s -X POST \
  "${SISENSE_API}/aUSAIAAaSwimmingIAAaTimesIAAaElasticube/jaql" \
  -H "Authorization: Bearer ${SISENSE_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"datasource\": {
      \"title\": \"USA Swimming Times Elasticube\",
      \"fullname\": \"LocalHost/USA Swimming Times Elasticube\"
    },
    \"metadata\": [
      {
        \"jaql\": {
          \"table\": \"UsasSwimTime\", \"column\": \"PersonKey\",
          \"dim\": \"[UsasSwimTime.PersonKey]\", \"datatype\": \"numeric\",
          \"title\": \"PersonKey\", \"filter\": {\"equals\": ${PERSON_KEY}}
        },
        \"panel\": \"scope\"
      },
      {
        \"jaql\": {
          \"table\": \"SwimEvent\", \"column\": \"EventCode\",
          \"dim\": \"[SwimEvent.EventCode]\", \"datatype\": \"text\",
          \"title\": \"Event\", \"filter\": {\"equals\": \"100 FR SCY\"}
        },
        \"panel\": \"scope\"
      },
      {
        \"jaql\": {
          \"table\": \"UsasSwimTime\", \"column\": \"SwimTimeFormatted\",
          \"dim\": \"[UsasSwimTime.SwimTimeFormatted]\", \"datatype\": \"text\",
          \"title\": \"Time\"
        }
      },
      {
        \"jaql\": {
          \"table\": \"UsasSwimTime\", \"column\": \"SortKey\",
          \"dim\": \"[UsasSwimTime.SortKey]\", \"datatype\": \"numeric\",
          \"title\": \"SortKey\"
        }
      },
      {
        \"jaql\": {
          \"table\": \"Meet\", \"column\": \"MeetName\",
          \"dim\": \"[Meet.MeetName]\", \"datatype\": \"text\",
          \"title\": \"Meet\"
        }
      }
    ],
    \"count\": 100,
    \"offset\": 0
  }")

# Print results sorted by SortKey (fastest first).
echo "100 Freestyle SCY — all times (fastest first):"
echo "-----------------------------------------------"
printf "%-10s  %s\n" "Time" "Meet"
echo "${TIMES_RESPONSE}" | jq -r '
  .values
  | sort_by(.[1].data)
  | .[]
  | "\(.[0].text)  \(.[2].text)"'
