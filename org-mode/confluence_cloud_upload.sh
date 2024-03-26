#!/bin/sh

# For Atlassian Cloud API access, you need to generate a token which
# takes the place of the password for the REST API authentication
#
#   https://id.atlassian.com/manage-profile/security/api-tokens
#   https://developer.atlassian.com/cloud/confluence/basic-auth-for-rest-apis/
#
# Dependencies:
#   basename, curl, cut, dirname, echo, egrep, emacs (of course), mktemp, perl (JSON:XS), sed, stty

if [ $# -ne 1 ]; then
    echo "Usage: $0 <org-file>" 1>&2
    exit 1
fi

ORGFILE="$1"

if [ ! -e "$ORGFILE" ]; then
    echo "$0: File not found '$ORGFILE'" 1>&2
    exit 1
fi

# Current variables expected in this file:
# - CONF_USER   - your Confluence username
# - CONF_TOKEN  - your Confluence API token
# - CONF_SPACE  - your default Confluence space
# - CONF_PARENT - your default parent page
# - CONF_SERVER - your confluence server
# - CONF_ELISP  - which (emacs) elisp file to load so that we can run
#                 org-confluence-export-as-confluence
source $HOME/.confluence.config

function strip_whitespace() {
    echo "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

function conf_check {
    # Check the API token
    OUTPUT=$(curl -s -u "$CONF_USER:$CONF_TOKEN" "$CONF_SERVER/rest/api/space")
    STATUSCODE=$(jq -r .statusCode <<< $OUTPUT)
    MESSAGE=$(jq -r .message <<< $OUTPUT)
    if [ "null" = "$STATUSCODE" ]; then
	return 0
    fi
    echo "API token check failed:"
    echo "  Status Code: $STATUSCODE"
    echo "  Message:     $MESSAGE"
    return 1
}

conf_check
if [ $? -gt 0 ]; then
    exit 1
fi

SPACE=$(egrep '^#\+confluence-space:' "$ORGFILE" | cut -d: -f2-)
# echo "SPACE: $SPACE"
if [ -z "$SPACE" ]; then
    # Fall back to default from ~/.confluence.config
    SPACE="$CONF_SPACE"
else
    SPACE=$(strip_whitespace "$SPACE")
fi
echo "Confluence space:       '$SPACE'" 1>&2

PARENT_PAGE=$(egrep '^#\+confluence-parent:' "$ORGFILE" | cut -d: -f2-)
# echo "PARENT_PAGE: $PARENT_PAGE"
if [ -z "$PARENT_PAGE" ]; then
    # Fall back to default from ~/.confluence.config
    PARENT_PAGE="$CONF_PARENT"
else
    PARENT_PAGE=$(strip_whitespace "$PARENT_PAGE")
fi
URLPARENT_PAGE=$(sed -e 's/ /+/g' <<< $PARENT_PAGE)

echo "Confluence parent page: '$PARENT_PAGE'" 1>&2
# echo "URL PARENT PAGE: $URLPARENT_PAGE"

TITLE=$(egrep '^#\+confluence-title:' "$ORGFILE" | cut -d: -f2-)
# echo "TITLE: $TITLE"
if [ -z "$TITLE" ]; then
    echo "$0: Missing confluence-title keyword in Org file." 1>&2
    exit 1
else
    TITLE=$(strip_whitespace "$TITLE")
fi

# This is a hack, not sure what else Confluence wants to be converted
URLTITLE=$(sed -e 's/ /+/g' <<< $TITLE)
echo "Confluence page title:  '$TITLE'"
# echo "URL TITLE: $URLTITLE"

WIKIFILE="$(dirname "$ORGFILE")/$(basename "$ORGFILE" .org).wiki"
echo "Confluence export file: '$WIKIFILE'"
if [ -e "$WIKIFILE" ]; then
    if [ "$WIKIFILE" -nt "$ORGFILE" ]; then
	echo "The export file is newer than the org file. Skipping upload." 1>&2
	exit 2
    fi
    echo "$0: Moving previous $WIKIFILE out of the way" 1>&2
    mv -f "$WIKIFILE" "$WIKIFILE.old"
fi

# Run the Confluence export function within Emacs:
#
# Instead of loading ~/.emacs it would probably suffice to load a
# different, minimal, file that just gets the org-confluence-*
# function working, but that wasn't worth exploring further at this
# time.
emacs \
    --batch \
    --load "$CONF_ELISP" \
    --visit "$ORGFILE" \
    --eval "(progn (org-confluence-export-as-confluence) (write-file \"$WIKIFILE\"))" > /dev/null 2>&1
if [ ! -e "$WIKIFILE" ]; then
    echo "$0: Confluence export failed? Aborting." 1>&2
    exit 1
fi

function remove_wikifile() {
    # Restore echoing, if we aborted in the middle of the password prompt.
    stty echo
    (
	echo
	echo "Something went wrong, deleting the (possibly) not uploaded Confluence export."
	echo
    ) 1>&2
    rm -f "$WIKIFILE"
    exit 1
}

trap remove_wikifile SIGINT

# Get the ID of the parent page:
PARENT_INFO=$(curl -s -u "$CONF_USER:$CONF_TOKEN" "$CONF_SERVER/rest/api/content?type=page&spaceKey=$SPACE&title=$URLPARENT_PAGE")
PARENT_ID=$(jq -r '.results[0].id' <<< $PARENT_INFO)
if [ "$PARENT_ID" = "null" ]; then
    echo "$0: Could not find the parent page." 1>&2
    echo "$PARENT_INFO"
    exit 1
fi

echo "$(date): Parent page ID: $PARENT_ID" 1>&2

# See if the target page already exists:
PAGE_DATA=$(curl -s -u "$CONF_USER:$CONF_TOKEN" "$CONF_SERVER/rest/api/content?type=page&spaceKey=$SPACE&title=$URLTITLE&expand=version")
PAGE_ID=$(jq -r '.results[0].id' <<< $PAGE_DATA)
PAGE_VERSION=$(jq -r '.results[0].version.number' <<< $PAGE_DATA)

# Using the cat <<EOF | ... approach until I can figure out why other
# methods that involve 'read' cause me to lose whitespace in
# significant (to me) places

# https://developer.atlassian.com/server/confluence/confluence-rest-api-examples/
# https://docs.atlassian.com/ConfluenceServer/rest/<version>/

if [ "$PAGE_ID" = "null" ]; then
    echo "$(date): Target page does not yet exist." 1>&2
    CONTENT="$(perl -MJSON::XS -e '$/=undef;$t=<>;print encode_json({value=>$t,representation=>"wiki"})' < $WIKIFILE)"
    OUTPUT=$(cat <<EOF | curl -s -u "$CONF_USER:$CONF_TOKEN" -X POST -H 'Content-Type: application/json' "$CONF_SERVER/rest/api/content" --data @- | jq ._links
{"type":"page","title":"$TITLE","ancestors":[{"id":"$PARENT_ID"}],"space":{"key":"$SPACE"},"body":{"storage":$CONTENT}}
EOF
          )
    if [ -n "$OUTPUT" ]; then
        echo "Visit the new page: $(jq -r '.base + .webui' <<< $OUTPUT)"
    else
        echo "Something went wrong while creating the page."
    fi
else
    echo "$(date): Target page ID: $PAGE_ID; Current version: $PAGE_VERSION" 1>&2
    # Bump the page version, or the new content will not be accepted.
    NEXT_VERSION=$(($PAGE_VERSION+1))
    CONTENT="$(perl -MJSON::XS -e '$/=undef;$t=<>;print encode_json({value=>$t,representation=>"wiki"})' < $WIKIFILE)"
    OUTPUT=$(cat <<EOF | curl -s -u "$CONF_USER:$CONF_TOKEN" -X PUT -H 'Content-Type: application/json' "$CONF_SERVER/rest/api/content/$PAGE_ID" --data @- | jq ._links
{"id":"$PAGE_ID","type":"page","title":"$TITLE","ancestors":[{"id":"$PARENT_ID"}],"space":{"key":"$SPACE"},"body":{"storage":$CONTENT},"version":{"number":$NEXT_VERSION}}
EOF
          )
    if [ -n "$OUTPUT" ]; then
        echo "Visit the updated page: $(jq -r '.base + .webui' <<< $OUTPUT)"
    else
        echo "Something went wrong while updating the page."
    fi
fi
