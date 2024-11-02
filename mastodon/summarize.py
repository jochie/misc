#!/usr/bin/env python3

"""
Take a look at your timeline (home timeline, or a specific list if you
want) and break down who posts or boosts the most, so you can make
informed decisions.
"""

import argparse
import json
import sys
import time
import urllib3

# A token is needed. The only scope it needs is:
#
# [x] Read
#     read all your account's data


def parse_options():
    """
    Parse the command line options/arguments
    """

    parser = argparse.ArgumentParser(
        description="""
Summarize recent posts on the "home" timeline, determine who posts or
boosts the most, or boosted the most.
""",
        epilog="""
To create a token, on the Mastodon web interface go to "Edit Profile",
"Development", and create a new application. The value of the 'Your
access token" row is what you need. The only scope required is "[x]
read".
"""
       )
    parser.add_argument('-d', '--debug',
                        help='Include additional debug output',
                        action='store_true')

    parser.add_argument('-s', '--server',
                        help="Hostname of the server to query",
                        required=True)
    parser.add_argument('-t', '--token',
                        help="Authentication token ('Read' scope only). Prefix with @ to read file",
                        required=True)

    parser.add_argument('--lists',
                        help="Fetch the lists in the account for the given token",
                        action='store_true')
    parser.add_argument('-l', '--list',
                        help="Fetch the list's timeline instead of the home timeline")
    parser.add_argument('--top',
                        help="Show the top X entries in each category",
                        default=10, type=int)
    parser.add_argument("--separate",
                        help="Use separate categories for 'posts' and 'replies to self'",
                        action='store_true')
    parser.add_argument("--max",
                        help="How many posts to fetch, at the most",
                        default=1000, type=int)

    opts = parser.parse_args()

    if opts.token and opts.token[0] == '@':
        try:
            with open(opts.token[1:], 'r', encoding="utf-8") as token_f:
                opts.token = token_f.read().strip()
                token_f.close()
        except IOError:
            print(f"Token file not found: {opts.token[1:]}")
            sys.exit(1)

    return opts


def stats_breakdown(category, acct, tracking):
    """
    Populate the 'stats' and 'breakdown' tracking data
    """

    tracking['stats'][category] += 1
    if acct not in tracking['breakdown'][category]:
        tracking['breakdown'][category][acct] = 0
    tracking['breakdown'][category][acct] += 1


def process_timeline_entry(opts, tracking, entry):
    """
    Analyze a timeline entry and decide which category it fits
    """

    if not tracking['oldest'] or entry['created_at'] < tracking['oldest']:
        tracking['oldest'] = entry['created_at']
    tracking['acct_ids'][entry['account']['id']] = entry['account']['acct']
    if opts.debug:
        pre = f"[{entry['id']}] {entry['created_at']}: "
    acct = entry['account']['acct']
    if "reblog" in entry and entry['reblog'] is not None:
        if opts.debug:
            print(f"{pre}Boost by {acct} of post by {entry['reblog']['account']['acct']}")
        stats_breakdown('boosts', acct, tracking)
        stats_breakdown('boosted', entry['reblog']['account']['acct'], tracking)
    elif 'in_reply_to_id' in entry and entry['in_reply_to_id'] is not None:
        if entry['in_reply_to_account_id'] == entry['account']['id']:
            if opts.debug:
                print(f"{pre}Reply by {acct}")
            stats_breakdown('threads', acct, tracking)
            stats_breakdown('combo', acct, tracking)
        else:
            if opts.debug:
                print(f"{pre}Reply by {acct}")
            stats_breakdown('replies', acct, tracking)
    else:
        if opts.debug:
            print(f"{pre}Post by {acct}")
        stats_breakdown('posts', acct, tracking)
        stats_breakdown('combo', acct, tracking)


def fetch_timeline(opts, http, tracking):
    """
    Make requests for (more) timeline data until we've reached the end
    of fetched the desired number of entries
    """

    max_id = None
    total = opts.max

    requests = 0
    if opts.list:
        timeline = f"list/{opts.list}"
    else:
        timeline = "home"
    url = f"https://{opts.server}/api/v1/timelines/{timeline}"

    while total > 0:
        if opts.debug:
            print(f"Fetching <{url}>...")
        extra = {
            'headers': { 'Authorization': f"Bearer {opts.token}" },
            'fields':  { 'limit': 40 }
        }
        if max_id:
            extra['fields']['max_id'] = max_id
        requests += 1
        result = http.request("GET", url, **extra)
        if result.status != 200:
            print(f"Unexpected HTTP status code for {result.url}: {result.status}")
            sys.exit(1)
        home_json = json.loads(result.data)
        last_id = None
        if opts.debug:
            print(f"==== Batch of posts prior to {max_id}")
        for entry in home_json:
            process_timeline_entry(opts, tracking, entry)

            last_id = entry['id']
            total -= 1
        if not last_id:
            # The Mastodon server doesn't track the various timelines
            # indefinitely so we typically get to the end before
            # having found the desired number of posts.
            break
        max_id = last_id

    # This needs to parse/match timestamps like this:
    # 2024-07-28T02:30:51.697Z
    tracking['oldest_stamp'] = time.mktime(time.strptime(tracking['oldest'],
                                                         "%Y-%m-%dT%H:%M:%S.%fZ"))
    tracking['duration'] = tracking['now'] - tracking['oldest_stamp']

    return opts.max - total, requests


def fetch_relations(opts, http, tracking):
    """
    The "relationships" information is fetched for the 'following' and
    'showing_reblogs' (boosts enabled) information
    """

    extra = {
        'headers': {
            'Authorization': f"Bearer {opts.token}"
        }
    }
    url = f"https://{opts.server}/api/v1/accounts/relationships"
    extra['fields'] = []
    for acct_id, _ in tracking['acct_ids'].items():
        extra['fields'].append(('id[]', acct_id))
    result = http.request("GET", url, **extra)

    for relation_data in json.loads(result.data):
        acct_id = relation_data['id']
        acct = tracking['acct_ids'][acct_id]
        tracking['relations'][acct] = relation_data


def top(opts, title, stat, tracking):
    """
    Show the top X entries of the particular stat type
    """
    stats     = tracking['stats']
    breakdown = tracking['breakdown']
    relations = tracking['relations']
    duration  = tracking['duration'] / 86400
    maximum   = opts.top

    print(f"  {title}: {stats[stat]} ({stats[stat] / duration:.1f} per day)")
    chart = breakdown[stat]
    accounts = chart.keys()
    accounts = sorted(accounts, key=lambda x: chart[x], reverse=True)
    for x, acct in enumerate(accounts):
        acct_display = acct
        if acct in relations:
            suffix = ""
            if relations[acct]['showing_reblogs'] is True:
                suffix += "B"
            if relations[acct]['following'] is True:
                suffix += "F"
            if suffix:
                acct_display += "[" + suffix + "]"

        print(f"    {acct_display:40} - {chart[acct]:3} [{chart[acct]/duration:4.1f}]")
        if x >= maximum:
            break
    print("")


def summarize(opts, tracking):
    """
    Present our findings
    """

    if tracking['now'] - tracking['oldest_stamp'] < 86400:
        print(f"Posts going back to {tracking['oldest']}; {tracking['duration']/3600:.1f} hour(s)")
    else:
        print(f"Posts going back to {tracking['oldest']}; {tracking['duration']/86400:.1f} day(s)")
    print("")

    print("Summary:")

    if opts.separate:
        top(opts, "Posts", 'posts', tracking)
        top(opts, "Replies to self", 'threads', tracking)
    else:
        top(opts, "Posts + replies to self", 'combo', tracking)

    top(opts, "Replies to others", 'replies', tracking)
    top(opts, "Boosts", 'boosts', tracking)
    top(opts, "Boosted", 'boosted', tracking)


def analyze_timeline(opts, http):
    """
    Fetch the desired timeline, fetch the relations data for the
    accounts seen in the timeline, and present our findings
    """

    tracking = {
        'now': time.time(),
        'stats': {
            'posts':   0,
            'replies': 0,
            'threads': 0,
            'combo':   0,
            'boosts':  0,
            'boosted': 0
        },
        'breakdown': {
            'posts':   {},
            'replies': {},
            'threads': {},
            'combo':   {},
            'boosts':  {},
            'boosted': {}
        },
        'acct_ids':  {},
        'duration':  0.0,
        'relations': {},
        'oldest': None
    }

    total, requests = fetch_timeline(opts, http, tracking)
    if total == 0:
        print("No posts found.")
        return

    if opts.debug:
        print(f"Fetched {total} posts in {requests} requests.")

    fetch_relations(opts, http, tracking)

    summarize(opts, tracking)


def get_lists(opts, http):
    """
    Fetch the lists for this user (if any).
    """

    url = f"https://{opts.server}/api/v1/lists"
    extra = {
        'headers': {
            'Authorization': f"Bearer {opts.token}"
        }
    }
    result = http.request("GET", url, **extra)
    print(json.dumps(json.loads(result.data), indent=2))


def main():
    """
    Main function/program
    """

    opts = parse_options()
    http = urllib3.PoolManager()

    if opts.lists:
        get_lists(opts, http)
        sys.exit(0)

    analyze_timeline(opts, http)


if __name__ == "__main__":
    main()
