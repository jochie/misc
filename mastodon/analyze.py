#!/usr/bin/env python3

"""
Use the Mastodon public APIs to fetch recent statuses (posts, replies,
boosts) and analyze what kind of output to expect from a certain
account.
"""

import argparse
import json
import os
import re
import sys
import time
import urllib3

def parse_options():
    """
    Parse the command line options/arguments
    """

    parser = argparse.ArgumentParser(
        description="""
""",
        epilog="""
"""
    )
    parser.add_argument("-d", "--debug",
                        help="Enable debug output",
                        default=False, action='store_true')
    parser.add_argument("-v", "--verbose",
                        help="Enable verbose output",
                        default=False, action='store_true')
    parser.add_argument("-u", "--user",
                        help="The Mastodon user",
                        required=True)
    parser.add_argument("-s", "--server",
                        help="The Mastodon server",
                        required=True)
    parser.add_argument("-m", "--max",
                        help="Limit the number of days of posts/replies/boosts to attempt to fetch",
                        default=7, type=int)
    opts = parser.parse_args()
    return opts


def get_acct_id(opts, http):
    """
    Kindly ask the server what obscure identifier it uses for a user
    """
    url = f"https://{opts.server}/api/v1/accounts/lookup?acct={opts.user}"

    result = http.request("GET", url)
    if result.status != 200:
        print(f"Unexpected HTTP status code for {result.url}: {result.status}")
        sys.exit(1)

    return json.loads(result.data)['id']


def get_list(opts, http, userid):
    """
    Fetch the initial page of (public) statuses for a specific user on a server
    """
    # Seems limit is supported, but a maximum of 40
    url = f"https://{opts.server}/api/v1/accounts/{userid}/statuses?limit=40"
    result = http.request("GET", url)
    if result.status != 200:
        print(f"Unexpected HTTP status code for {result.url}: {result.status}")
        sys.exit(1)
    return result.headers["Link"], json.loads(result.data)


def get_next_page(_opts, http, url):
    """
    Fetch subsequent pages of (public) statuses
    """
    result = http.request("GET", url)
    if result.status != 200:
        print(f"Unexpected HTTP status code: {result.status}")
        sys.exit(1)
    return result.headers["Link"], json.loads(result.data)


def parse_link_data(opts, data):
    """
    Parse the 'link' header into "next" and "prev" entries
    """
    result = {}
    parts = re.split(r",\s+", data)
    for part in parts:
        bits = re.match(r"<([^>]+)>; rel=\"(next|prev)\"", part)
        if opts.debug:
            print(f"Link entry: {bits.group(1)} => {bits.group(2)}")
        if bits.group(2) == 'next':
            result["next"] = bits.group(1)
        elif bits.group(2) == 'prev':
            result["prev"] = bits.group(1)

    return result


def process_entry(opts, userid, stats, entry):
    """
    Examine a single status (post, reply, boost) and update our stats
    """
    stats['total'] += 1
    if opts.debug or opts.verbose:
        pre = f"[{entry['id']}] {entry['created_at']}: "
    if not stats['oldest'] or entry['created_at'] < stats['oldest']:
        stats['oldest'] = entry['created_at']
    acct = entry['account']['acct']
    if "reblog" in entry and entry["reblog"] is not None:
        if opts.debug or opts.verbose:
            print(f"{pre}Boost by {acct} of post by {entry['reblog']['account']['acct']}")
        stats['boosts'] += 1
    elif 'in_reply_to_id' in entry and entry['in_reply_to_id'] is not None:
        if entry['in_reply_to_account_id'] == userid:
            if opts.debug or opts.verbose:
                print(f"{pre}Thread-reply by {acct}")
            stats['threads'] += 1
        else:
            mentions = [ mention['acct'] for mention in entry['mentions']]
            if opts.debug or opts.verbose:
                print(f"{pre}Reply to {', '.join(mentions)} by {acct}")
            stats['replies'] += 1
    else:
        if opts.debug or opts.verbose:
            print(f"{pre}Post by {acct}")
        stats['posts'] += 1

    oldest_struct = time.strptime(stats['oldest'], "%Y-%m-%dT%H:%M:%S.%fZ")
    oldest_stamp = time.mktime(oldest_struct)
    dur = time.time() - oldest_stamp
    return dur >= opts.max * 86400


def analyze_timeline(opts, http, userid):
    """
    Fetch enough of the timeline, track stats as we go
    """
    stats = {
        'boosts':  0,
        'replies': 0,
        'posts':   0,
        'threads': 0,
        'oldest':  None,
        'total':   0,
        'batch':   0
    }
    link_data, json_data = get_list(opts, http, userid)
    while len(json_data) > 0:
        stats['batch'] += 1
        if opts.debug:
            print(f"#messages in batch {stats['batch']}: {len(json_data)}")
        for entry in json_data:
            if process_entry(opts, userid, stats, entry):
                break
        oldest_struct = time.strptime(stats['oldest'], "%Y-%m-%dT%H:%M:%S.%fZ")
        oldest_stamp = time.mktime(oldest_struct)
        dur = time.time() - oldest_stamp
        if dur >= opts.max * 86400:
            break

        rel_data = parse_link_data(opts, link_data)
        if 'next' not in rel_data:
            break
        link_data, json_data = get_next_page(opts, http, rel_data['next'])

    oldest_struct = time.strptime(stats['oldest'], "%Y-%m-%dT%H:%M:%S.%fZ")
    oldest_stamp = time.mktime(oldest_struct)
    dur = time.time() - oldest_stamp
    print(f"Oldest post/boost/reply/thread: {stats['oldest']}")
    print(f"This covers {dur:.1f} seconds, {dur/3600:.1f} hour(s), or {dur/86400:.1f} day(s)")
    daypart = dur / 86400
    combined = stats['posts'] + stats['threads']
    print(f"Posts + threads: {combined:4} ({combined/daypart:5.1f} per day)")
    print(f"Boosts:          {stats['boosts']:4} ({stats['boosts']/daypart:5.1f} per day)")
    print(f"Replies:         {stats['replies']:4} ({stats['replies']/daypart:5.1f} per day)")

def main():
    """
    Main function/program
    """

    os.environ['TZ'] = 'UTC'
    time.tzset()
    opts = parse_options()
    http = urllib3.PoolManager()

    userid = get_acct_id(opts, http)
    analyze_timeline(opts, http, userid)


if __name__ == "__main__":
    main()
