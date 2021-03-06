package Melody::API::Twitter::Status;

use base qw( Melody::API::Twitter );
use Melody::API::Twitter::Util
  qw( serialize_author twitter_date truncate_tweet serialize_entries is_number load_friends load_followers latest_status mark_favorites );

###########################################################################

=head2 statuses/public_timeline

Returns the 20 most recent statuses from non-protected users who have set a custom user icon. 
The public timeline is cached for 60 seconds so requesting it more often than that is a waste 
of resources.

URL: http://<api base URL>/statuses/public_timeline.<format>
 
Formats: xml, json, rss, atom 
 
Requires Authentication: false
 
API rate limited: true
 
Response: An array statuses.

=cut

sub public_timeline {
    my $app      = shift;
    my ($params) = @_;      # this method takes no input
    my $terms    = {};
    my $args     = {
        sort_by   => 'created_on',
        direction => 'descend',
    };
    my $iter = MT->model('entry')->load_iter( $terms, $args ); # load everything
    my @entries;
    my $n = 20;
    my $i = 0;
  ENTRY: while ( my $e = $iter->() ) {
        push @entries, $e;
        $i++;
        $iter->end, last if $n && $i >= $n;
    }
    my $statusus;
    $statuses = serialize_entries( \@entries );
    return { statuses => { status => $statuses } };
}

###########################################################################

=head2 statuses/home_timeline

Returns the 20 most recent statuses, including retweets, posted by the authenticating user and 
that user's friends. This is the equivalent of /timeline/home on the Web.

Usage note: This home_timeline is identical to statuses/friends_timeline except it also contains 
retweets, which statuses/friends_timeline does not (for backwards compatibility reasons). In a 
future version of the API, statuses/friends_timeline will go away and be replaced by home_timeline.
 
URL: http://<base api URL>/1/statuses/home_timeline.<format>
 
Formats: xml, json, atom 
 
HTTP Method(s): GET
 
Requires Authentication: true
 
API rate limited: 1 call per request
 
B<Parameters:>

=over 4

=item since_id

Optional.  Returns only statuses with an ID greater than (that is, more recent than) the specified ID. 

=item max_id

Optional.  Returns only statuses with an ID less than (that is, older than) or equal to the specified ID.

=item count

Optional.  Specifies the number of statuses to retrieve. May not be greater than 200. 

=item page

Optional. Specifies the page of results to retrieve. Note: there are pagination limits.

=back
 
=cut

# TODO - filter home_timeline by current user's tweets and their "friends"

sub home_timeline {
    my $app = shift;
    return unless $app->SUPER::authenticate(AUTH_REQUIRED);
    my ($params) = @_;
    my $terms    = {};
    my $args     = {
        sort_by   => 'created_on',
        direction => 'descend',
    };
    my $n    = 20;
    my $page = 1;
    if (   $params->{count}
        && is_number( $params->{count} )
        && $params->{count} <= 200 )
    {
        $n = $params->{count};
    }
    if ( $params->{max_id} ) {
        $terms->{id} = { '<=' => $params->{max_id} };
    }
    if ( $params->{since_id} ) {
        $terms->{id} = { '>' => $params->{since_id} };
    }
    if ( $params->{page} && is_number( $params->{page} ) ) {
        $page = $params->{page};
    }
    $args->{limit} = $n;
    $args->{offset} = ( $n * ( $page - 1 ) ) if $page > 1;

    my $friends = load_friends( $app->user );
    $friends{ $app->user->id } = $app->user;
    my @friends_ids = keys %$friends;
    $terms->{author_id} = \@friends_ids;

    my $iter = MT->model('entry')->load_iter( $terms, $args ); # load everything
    my @entries;

    my $i = 0;
  ENTRY: while ( my $e = $iter->() ) {
        push @entries, $e;
        $i++;

        #      $iter->end, last if $n && $i >= $n;
    }
    my $statusus;
    $statuses = serialize_entries( \@entries );
    mark_favorites( $statuses, $app->user );
    return { statuses => { status => $statuses } };
}

###########################################################################

=head2 statuses/user_timeline 

Returns the 20 most recent statuses posted from the authenticating user. It's 
also possible to request another user's timeline via the id parameter. This is 
the equivalent of the Web /<user> page for your own user, or the profile page 
for a third party.

Note: For backwards compatibility reasons, retweets are stripped out of the 
user_timeline when calling in XML or JSON (they appear with 'RT' in RSS and Atom). 
If you'd like them included, you can merge them in from statuses retweeted_by_me.
 
URL: http://twitter.com/statuses/user_timeline.format
 
Formats: xml, json, rss, atom 
 
HTTP Method(s): GET
 
Requires Authentication: true, if requesting a protected user's timeline
 
API rate limited: 1 call per request
 
B<Parameters:>

=over 4

=item id

Optional.  Specifies the ID or screen name of the user for whom to return the user_timeline. 

=item user_id

Optional.  Specfies the ID of the user for whom to return the user_timeline. Helpful for disambiguating when a valid user ID is also a valid screen name.

=item screen_name

Optional.  Specfies the screen name of the user for whom to return the user_timeline. Helpful for disambiguating when a valid screen name is also a user ID.

=item since_id

Optional.  Returns only statuses with an ID greater than (that is, more recent than) the specified ID. 

=item max_id

Returns only statuses with an ID less than (that is, older than) or equal to the specified ID.

=item count

Optional.  Specifies the number of statuses to retrieve. May not be greater than 200. (Note the the number of statuses returned may be smaller than the requested count as retweets are stripped out of the result set for backwards compatibility.)

=item page

Optional. Specifies the page of results to retrieve. Note: there are pagination limits.

=back
 
B<Usage notes:>

You will only be able to access the latest 3200 statuses from a user's timeline due to pagination limits.
 
=cut

sub user_timeline {
    my $app       = shift;
    my $is_authed = $app->SUPER::authenticate(AUTH_OPTIONAL);
    my ($params)  = @_;
    my $terms     = {};
    my $args      = {
        sort_by   => 'created_on',
        direction => 'descend',
    };

    # Validate input
    if ( !$params->{user_id} && !$params->{screen_name} && $is_authed ) {

        # TODO - authenticate and set current context to current user
        $params->{user_id} = $app->user->id;
    }

    my $n    = 20;
    my $page = 1;
    if (   $params->{count}
        && is_number( $params->{count} )
        && $params->{count} <= 200 )
    {
        $n = $params->{count};
    }
    if ( $params->{user_id} ) {
        my $user = MT->model('author')->load( { name => $params->{user_id} } );
        unless ($user) {
            return $app->error( 404,
                'User ' . $params->{user_id} . ' not found.' );
        }
        $terms->{author_id} = $params->{user_id};
    }

    if ( $params->{screen_name} ) {
        my $join_str = '=entry_author_id';
        $args->{join} = MT->model('author')->join_on(
            undef,
            {
                'id'   => \$join_str,
                'name' => $params->{screen_name},
            }
        );
    }
    if ( $params->{max_id} ) {
        $terms->{id} = { '<=' => $params->{max_id} };
    }
    if ( $params->{since_id} ) {
        $terms->{id} = { '>' => $params->{since_id} };
    }
    if ( $params->{page} && is_number( $params->{page} ) ) {
        $page = $params->{page};
    }
    $args->{limit} = $n;
    $args->{offset} = ( $n * ( $page - 1 ) ) if $page > 1;

    my $iter = MT->model('entry')->load_iter( $terms, $args ); # load everything
    my @entries;

    my $i = 0;
  ENTRY: while ( my $e = $iter->() ) {
        push @entries, $e;
        $i++;

        #      $iter->end, last if $n && $i >= $n;
    }
    my $statusus;
    $statuses = serialize_entries( \@entries );
    return { statuses => { status => $statuses } };
}

###########################################################################

=head2 statuses/friends_timeline
=cut

sub friends_timeline {
    my $app = shift;
    return unless $app->SUPER::authenticate();
    my ($params) = @_;
    my $terms    = {};
    my $args     = {
        sort_by   => 'created_on',
        direction => 'descend',
    };
    my $n    = 20;
    my $page = 1;
    if (   $params->{count}
        && is_number( $params->{count} )
        && $params->{count} <= 200 )
    {
        $n = $params->{count};
    }
    if ( $params->{max_id} ) {
        $terms->{id} = { '<=' => $params->{max_id} };
    }
    if ( $params->{since_id} ) {
        $terms->{id} = { '>' => $params->{since_id} };
    }
    if ( $params->{page} && is_number( $params->{page} ) ) {
        $page = $params->{page};
    }
    $args->{limit} = $n;
    $args->{offset} = ( $n * ( $page - 1 ) ) if $page > 1;

    my $friends     = load_friends( $app->user );
    my @friends_ids = keys %$friends;
    $terms->{author_id} = \@friends_ids;

    my $iter = MT->model('entry')->load_iter( $terms, $args ); # load everything
    my @entries;

    my $i = 0;
  ENTRY: while ( my $e = $iter->() ) {
        push @entries, $e;
        $i++;

        #      $iter->end, last if $n && $i >= $n;
    }
    my $statusus;
    $statuses = serialize_entries( \@entries );
    return { statuses => { status => $statuses } };
}

###########################################################################

=head2 statuses/mentions
=cut

###########################################################################

=head2 statuses/retweeted_by_me
=cut

###########################################################################

=head2 statuses/retweeted_to_me
=cut

###########################################################################

=head2 statuses/retweets_of_me
=cut

###########################################################################

=head2 statuses/show

Returns a single status, specified by the id parameter below.  The status's author will be returned inline.
 
URL: http://twitter.com/statuses/show/id.format
 
Formats: xml, json
 
HTTP Method(s): GET
 
Requires Authentication: false, unless the author of the status is protected
 
API rate limited: true
 
B<Parameters:>

=over 4

=item id

Required.  The numerical ID of the status to retrieve. 

=back

=cut

sub show {
    my $app = shift;

    # TODO - auth only if post is protected
    #    return unless $app->SUPER::authenticate();
    my ($params) = @_;
    my $id;
    if ( $params->{id} && is_number( $params->{id} ) ) {
        $id = $params->{id};
    }
    else {
        return $app->error( 404, 'No status message specified.' );
    }
    my $e = MT->model('entry')->load($id);      # load everything
    my $statuses = serialize_entries( [$e] );
    return { status => @$statuses[0] };
}

###########################################################################

=head2 statuses/update

Updates the authenticating user's status.  Requires the status parameter specified 
below.  Request must be a POST.  A status update with text identical to the authenticating 
user's current status will be ignored to prevent duplicates.
 
URL: http://twitter.com/statuses/update.format
 
Formats: xml, json
 
HTTP Method(s): POST
 
Requires Authentication: true
 
API rate limited: false
 
B<Parameters:>

=over 4

=item status

Required.  The text of your status update. URL encode as necessary. Statuses over 
140 characters will be forceably truncated.

=item in_reply_to_status_id

Optional. The ID of an existing status that the update is in reply to.

Note: This parameter will be ignored unless the author of the tweet this parameter 
references is mentioned within the status text. Therefore, you must include @username, 
where username is the author of the referenced tweet, within the update.

=item lat

Optional. The location's latitude that this tweet refers to.

Note: The valid ranges for latitude is -90.0 to +90.0 (North is positive) inclusive.  
This parameter will be ignored if outside that range, if it is not a number, if 
geo_enabled is disabled, or if there not a corresponding long parameter with this tweet.

The number of digits passed the decimal points passed to lat, up to 8, will be tracked 
so that the lat is returned in a status object it will have the same number of digits 
after the decimal point.

=item long

Optional. The location's longitude that this tweet refers to.

Note: The valid ranges for longitude is -180.0 to +180.0 (East is positive) inclusive.  
This parameter will be ignored if outside that range, if it is not a number, if geo_enabled 
is disabled, or if there not a corresponding lat parameter with this tweet.

The number of digits passed the decimal points passed to long, up to 8, will be tracked so 
that the long is returned in a status object it will have the same number of digits after 
the decimal point.
 
B<Usage Notes:>

This method is subject to update limits. A HTTP 403 will be returned if this limit as been hit.

Twitter will ignore attempts to perform a duplicate update. With each update attempt, the 
application compares the update text with the authenticating user's last successful update, 
and ignores any attempts that would result in duplication. Therefore, a user cannot submit the 
same status twice in a row. The status element in the response will return the id from the 
previously successful update if a duplicate has been silently ignored.
 
B<Geo-tagging:>

Any geo-tagging parameters in the update will be ignored if geo_enabled for the user is false 
(this is the default setting for all users unless the user has enabled geolocation in their 
settings)

The XML response uses GeoRSS to encode the latitude and longitude. <georss:point> encodes as 
latitude, space, and longitude (see the response below for an example).  For JSON, the 
response mostly uses conventions laid forth in GeoJSON.  Unfortunately, the coordinates 
that Twitter renderers are reversed from the GeoJSON specification (GeoJSON specifies a 
longitude then a latitude, whereas we are currently representing it as a latitude then a 
longitude.  This will be repaired in version 2 of the Twitter API.).  Our JSON renders as:

  "geo":
  {
  "type":"Point",
  "coordinates":[37.78029, -122.39697]
  }

If there is no geotag for a status, then there will be an empty <geo/> or "geo" : {}. 
Users will have the ability, from their settings page, to remove all the geotags from 
all their tweets en masse.  Currently we are not doing any automatic scrubbing nor 
providing a method to remove geotags from individual tweets.

=cut

sub update {
    my $app = shift;
    my ($params) = @_;    # this method takes no input

    return unless $app->SUPER::authenticate(AUTH_REQUIRED);

    my ( $msg, $in_reply_to, $lat, $long );
    if ( $app->request_method ne 'POST' ) {

        # TODO - reject request
    }
    if ( $params->{status} ) {
        $msg = $params->{status};
    }
    else {
        return $app->error( 500, 'No status message provided.' );
    }
    if ( $params->{in_reply_to_status_id} ) {
        $in_reply_to = $params->{in_reply_to_status_id};
    }
    if ( $params->{lat} ) {
        $lat = $params->{lat};
        unless ( $lat <= 90 && $lat >= -90 ) {
            return $app->error( 500,
                'Invalid range for latitude. Must be between 90.0 and -90.0.' );
        }
    }
    if ( $params->{long} ) {
        $long = $params->{long};
        unless ( $long <= 180 && $long >= -180 ) {
            return $app->error( 500,
                'Invalid range for longitude. Must be between 180.0 and -180.0.'
            );
        }
    }
    if ( $lat xor $long ) {
        return $app->error( 500, 'Must provide latitude and longitude.' );
    }

# TODO perform dupe check: retrieve last update, compare text, return 403 if same
    my $truncated;
    ( $truncated, $msg ) = truncate_tweet($msg);

    print STDERR "Saving tweet: $msg";
    my $e = MT->model('entry')->new;
    $e->title($msg);
    $e->author_id( $app->user->id );
    $e->status( MT->model('entry')->RELEASE() );

    # TODO - the blog id must not be static
    $e->blog_id(5);

    if ( $lat && $long ) {
        $e->geo_latitude($lat);
        $e->geo_longitude($long);
    }

    $e->save;
    print STDERR "Tweet saved with id: " . $e->id;
    my $statuses = serialize_entries( [$e] );
    return { status => @$statuses[0] };
}

###########################################################################

=head2 statuses/destroy  
=cut

sub destroy {
    my $app = shift;
    my ($params) = @_;    # this method takes no input
    return unless $app->SUPER::authenticate(AUTH_REQUIRED);

    my $id = $params->{id};
    my $e  = MT->model('entry')->load($id);
    unless ($e) {
        return $app->error( 404, 'Status message ' . $id . ' not found.' );
    }
    if ( $e->author_id == $app->user->id ) {
        $e->remove;
    }
    return { status => serialize_entries( [$e] ) };
}

###########################################################################

=head2 statuses/retweet
=cut

###########################################################################

=head2 statuses/retweets
=cut

###########################################################################

=head2 statuses/friends

Returns a user's friends, each with current status inline. They are ordered 
by the order in which the user followed them, most recently followed first, 
100 at a time. (Please note that the result set isn't guaranteed to be 100 
every time as suspended users will be filtered out.) Use the cursor option 
to access older friends. With no user specified, request defaults to the 
authenticated user's friends. It's also possible to request another user's 
friends list via the id, screen_name or user_id parameter.
  
URL: http://twitter.com/statuses/friends.format
 
Formats: xml, json
 
HTTP Method(s): GET
 
Requires Authentication: false unless requesting it from a protected user; if 
getting this data of a protected user, you must auth (and be allowed to see that user).
 
API rate limited: 1 call per request
 
B<Parameters:>

=over 4

=item id

Optional.  The ID or screen name of the user for whom to request a list of friends. 

=item user_id

Optional.  Specfies the ID of the user for whom to return the list of friends. 
Helpful for disambiguating when a valid user ID is also a valid screen name.

=item screen_name

Optional.  Specfies the screen name of the user for whom to return the list of friends. 
Helpful for disambiguating when a valid screen name is also a user ID.

=item cursor

Optional. Breaks the results into pages. A single page contains 100 users. This is 
recommended for users who are following many users. Provide a value of  -1 to begin 
paging. Provide values as returned to in the response body's next_cursor and 
previous_cursor attributes to page back and forth in the list.

=back

=cut

sub friends {
    my $app = shift;
    my ($params) = @_;    # this method takes no input

    my $is_authed = $app->SUPER::authenticate(AUTH_OPTIONAL);

    my $id;
    if ( $params->{id} ) {
        if ( is_number( $params->{id} ) ) {
            $id = $params->{id};
        }
        else {
            my $user = MT->model('author')->load( { name => $params->{id} } );
            unless ($user) {
                return $app->error( 404,
                    'User ' . $params->{id} . ' not found.' );
            }
            $id = $user->id;
        }
    }
    if ( $params->{user_id} && is_number( $params->{user_id} ) ) {
        $id = $params->{user_id};
    }
    if ( $params->{screen_name} ) {
        my $user =
          MT->model('author')->load( { name => $params->{screen_name} } );
        unless ($user) {
            return $app->error( 404,
                'User ' . $params->{screen_name} . ' not found.' );
        }
        $id = $user->id;
    }
    unless ($id) {
        if ($is_authed) {
            $id = $app->user->id;
        }
        else {
            return $app->SUPER::auth_failure( 403,
                "No user's timeline specified." );
        }
    }

    my ($params) = @_;
    my $terms    = {};
    my $args     = {
        sort_by   => 'created_on',
        direction => 'descend',
    };
    my $n      = 100;
    my $page   = 1;
    my $cursor = 0;
    if ( $params->{cursor} ) {

        # TODO - implement cursor
        $cursor = $params->{cursor};
    }
    $args->{limit} = $n;
    $args->{offset} = ( $n * ( $page - 1 ) ) if $page > 1;

    my $friends = load_friends($id);
    unless ($friends) {
        return { users => undef };
    }
    my @friends_ids = keys %$friends;
    $terms->{id} = \@friends_ids;

    my $iter =
      MT->model('author')->load_iter( $terms, $args );    # load everything
    my @users;

    my $hash;
    my $i = 0;
  ENTRY: while ( my $u = $iter->() ) {
        push @users, $u;
        my $uh     = serialize_author($u);
        my $latest = latest_status($u);
        if ($latest) {
            $uh->{status} = serialize_entries( [$latest] )->[0];
            delete %$uh->{status}->{user};
        }
        push @{ $hash->{users}->{user} }, $uh;
        $i++;

        #      $iter->end, last if $n && $i >= $n;
    }
    if ($cursor) {

        # TODO - fully implement cursor
        return {
            users_list => {
                users           => $hash,
                next_cursor     => '',
                previous_cursor => '',
            },
        };
    }
    return $hash;
}

###########################################################################

=head2 statuses/followers

=cut 

sub followers {
    my $app = shift;
    return unless $app->SUPER::authenticate();

    my ($params) = @_;
    my $terms    = {};
    my $args     = {
        sort_by   => 'created_on',
        direction => 'descend',
    };
    my $n      = 100;
    my $page   = 1;
    my $cursor = 0;
    if ( $params->{cursor} ) {

        # TODO - implement cursor
        $cursor = $params->{cursor};
    }
    $args->{limit} = $n;
    $args->{offset} = ( $n * ( $page - 1 ) ) if $page > 1;

    my $followers     = load_followers( $app->user );
    my @followers_ids = keys %$followers;
    $terms->{id} = \@followers_ids;

    my $iter =
      MT->model('author')->load_iter( $terms, $args );    # load everything
    my @users;

    my $hash;
    my $i = 0;
  ENTRY: while ( my $u = $iter->() ) {
        push @users, $u;
        my $uh     = serialize_author($u);
        my $latest = latest_status($u);
        if ($latest) {
            $uh->{status} = serialize_entries( [$latest] )->[0];
            delete %$uh->{status}->{user};
        }
        push @{ $hash->{users}->{user} }, $uh;
        $i++;

        #      $iter->end, last if $n && $i >= $n;
    }
    if ($cursor) {

        # TODO - fully implement cursor
        return {
            users_list => {
                users           => $hash,
                next_cursor     => '',
                previous_cursor => '',
            },
        };
    }
    return $hash;
}

1;
__END__
