#!/bin/sh

echo=/bin/echo

export AWS_PROFILE=your-account
export AWS_DEFAULT_REGION=your-region

function wait_for_state() {
    ID="$1"
    DESIRED_STATE="$2"

    while true; do
	$echo -n '.'
	JSON=$(aws ec2 describe-instances \
		   --instance-ids "$ID" | \
		   jq .Reservations[0].Instances[0])
	ec2_state=$(jq -r -C .State.Name <<< "$JSON")
	if [ "$DESIRED_STATE" = "$ec2_state" ]; then
	    echo " Instance state is now '$DESIRED_STATE'."
	    break
	fi
    done
}

function stop_instance() {
    ID="$1"
    aws ec2 stop-instances --instance-ids "$ID"

    wait_for_state "$ID" "stopped"
}

function start_instance() {
    ID="$1"
    aws ec2 start-instances --instance-ids "$ID"

    wait_for_state "$ID" "running"
}

JSON=$(aws \
	   ec2 describe-instances \
	   --filters Name=tag:Name,Values=Mastodon/frontend | \
	   jq .Reservations[0].Instances[0])

ec2_id=$(jq -r -C .InstanceId <<< "$JSON")
ec2_type=$(jq -r -C .InstanceType <<< "$JSON")
ec2_state=$(jq -r -C .State.Name <<< "$JSON")

echo "$(date): ID $ec2_id; Type $ec2_type; State: $ec2_state"

if [ "t4g.small" != "$ec2_type" ]; then
    echo "$0: Current EC2 type isn't 't4g.small'. Check this manually." 1>&2
    exit 1
fi

if [ "running" != "$ec2_state" ]; then
    echo "$0: Current state isn't 'running'. Check this manually." 1>&2
    exit 1
fi

$echo -n "$(date): Press enter to stop the Mastodon instance to upsize: "
read

stop_instance "$ec2_id"

echo "$(date): Changing instance type to t4g.medium..."

aws \
    ec2 modify-instance-attribute \
    --instance-id "$ec2_id" \
    --instance-type "t4g.medium"

echo "$(date): Starting instance back up..."
start_instance "$ec2_id"

$echo -n "$(date): Press enter to stop the Mastodon instance to downsize: "
read

stop_instance "$ec2_id"

echo "$(date): Changing instance type to t4g.small..."

aws \
    ec2 modify-instance-attribute \
    --instance-id "$ec2_id" \
    --instance-type "t4g.small"

echo "$(date): Starting instance back up..."
start_instance "$ec2_id"

echo "$(date): DONE"
