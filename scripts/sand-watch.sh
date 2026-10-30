#!/usr/bin/env bash

# Inject common local paths so launchd can discover your tools
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/Users/guygrigsby/.local/bin:$PATH"

# Start listening to Rex's live structural event stream
rex event stream | while read -r line; do
    
    # Detect when a child program has completed running inside a block
    if echo "$line" | grep -q '"event":"child_exited"'; then
        
        # Parse out the exit code using standard JSON filtering
        EXIT_CODE=$(echo "$line" | sed -n 's/.*"exit_code":\([0-9]\+\).*/\1/p')
        
        if [ "$EXIT_CODE" -eq 0 ]; then
            rex notify "Sandbox task completed. Auto-triggering 'sand up'..."
            sand up
        else
            rex notify "Sandbox task failed. Running 'sand ci pull'..."
            sand ci pull
        fi
    fi
done

