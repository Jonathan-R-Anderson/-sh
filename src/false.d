module cmd_false;

import core.stdc.stdlib : exit;

/// Do nothing and return a failure status.
void main(string[] args)
{
    exit(1);
}
