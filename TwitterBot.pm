package TwitterBot;

use utf8;
use strict;
use warnings;
use 5.010;
use LWP::UserAgent; # to shrink links
use Bot::BasicBot;
use Net::Twitter;
use Redis; 			# for authorizations
use Try::Tiny;

# this class is now a bot !
use base qw( Bot::BasicBot );

# process other's messages
sub said {
  my ($self, $msg) = @_;

  return unless $msg->{body} =~ /^\@/;

  # twitter link
  my $twlk = Net::Twitter->new(
    traits   => [qw/OAuth API::RESTv1_1/],
	ssl 	 => 1,
    consumer_key        => $self->{consumer_key},
    consumer_secret     => $self->{consumer_secret},
    access_token        => $self->{token},
    access_token_secret => $self->{token_secret}
  );

  # redis link
  my $redis_db = $self->{redis_db};
  my $redis_pref = $self->{redis_pref};
  my $masters = $self->{masters};
	my $masters_str = join ', ',@$masters;

  my $rdb = Redis->new();
  $rdb->select($redis_db);


  # if it's from a known nick and the length is OK...
  if ($msg->{body} =~ /^\@tweet\s*(.+)$/) {
    utf8::encode($1) if(! utf8::is_utf8($1));
    if ($rdb->get($redis_pref.$msg->{who})) {
      if (length($1) > 140) {
        $self->say(
          who => $msg->{who},
          channel => $msg->{channel},
          body => "Un peu long, ".length($1)." au lieu de 140..."
        );
        return;
      }

      # update twitter account...
	  try {
		  my $status = $twlk->update($1);
		  $self->say(
			who => $msg->{who},
			channel => $msg->{channel},
			body => "C'est parti ! ( https://twitter.com/manuelvalls/status/".$status->{id_str}." ) ID : ".$status->{id_str}
		  );
	  } catch {
		  $self->say(
			  who => $msg->{who},
			  channel => $msg->{channel},
			  body => "Erreur : $_"
		  );
	  };
      return;

      # if poster's not in allowed nicks
    } else {
      $self->say(
        who => $msg->{who},
        channel => $msg->{channel},
        body => "On se connait ?"
      );
      return;
    }
  }

  # @who
  if ($msg->{body} =~ /^\@who\s*$/) {
    my @keys = map {my @a = split(/:/); $_ = $a[1]} $rdb->keys('*'.$redis_pref.'*');
    my $body = '';
    foreach my $i (@keys) {
      $body .= ' '.$i if ($i ne 'last_twid');
    }

    $self->say(
      channel => $msg->{channel},
      body => 'Les twolleurs :'.$body
    );
  }

  # retweet
  if ($msg->{body} =~ /^\@retweet\s*(\d+|last)$/) {
    if ($rdb->get($redis_pref.$msg->{who})) {

      # update twitter account...
	  my $twid;
	  if ($1 eq "last") {
		  $twid = $rdb->get($redis_pref."last_twid");
	  } else {
		  $twid = $1;
	  }
      eval { $twlk->retweet($twid); };
      if ( $@ ) {
        $self->say(
          who => $msg->{who},
          channel => $msg->{channel},
          body => "ping ".$masters_str." il y a un petit souci... [ ".$@->error." ]",
        );
		use Data::Dumper;
		print(Dumper($@));
        return;
      } else {
        $self->say(
          who => $msg->{who},
          channel => $msg->{channel},
          body => "Retweet done ! ( https://twitter.com/bcazeneuve/status/".$twid." ) ID : ".$twid
        );
        return;
      }

      # if poster's not in allowed nicks
    } else {
      $self->say(
        who => $msg->{who},
        channel => $msg->{channel},
        body => "On se connait ?"
      );
      return;
    }
  }

  # reply
  if ($msg->{body} =~ /^\@reply\s*(\d+|last)\s*(.+)$/)
  {
    utf8::encode($2) if(! utf8::is_utf8($2));

    if ($rdb->get($redis_pref.$msg->{who})) {
	  # update twitter account...
	  my $twid;
	  if ($1 eq "last") {
	  	$twid = $rdb->get($redis_pref."last_twid");
	  } else {
	  	$twid = $1;
	  }
      if (length($2) > 140) {
        $self->say(
          who => $msg->{who},
          channel => $msg->{channel},
          body => "Un peu long, ".length($2)." au lieu de 140..."
        );
        return;
      }

      # update twitter account...
      my $status = $twlk->update($2,{in_reply_to_status_id => $twid});
	  $self->say(
		  who => $msg->{who},
		  channel => $msg->{channel},
		  body => "On répond à https://twitter.com/RoyalSegolene/status/".$twid
	  );
      $self->say(
        who => $msg->{who},
        channel => $msg->{channel},
        body => "C'est parti ! (https://twitter.com/JY_LeDrian/status/".$status->{id_str}.") ID : ".$status->{id_str}
      );
      return;
    } else {
      $self->say(
        who => $msg->{who},
        channel => $msg->{channel},
        body => "On se connait ?"
      );
      return;
    }
  }

  # Delete a status by his 'id'
  if ($msg->{body} =~ /^\@delete\s*(\d+)$/) {
    if ($rdb->get($redis_pref.$msg->{who})) {

      # update twitter account...
      eval { $twlk->destroy_status($1); };
      if ( $@ ) {
        $self->say(
          who => $msg->{who},
          channel => $msg->{channel},
          body => "ping ".$masters_str." il y a un petit souci... [ ".$@->error." ]",
        );
        return;
      } else {
        $self->say(
          who => $msg->{who},
          channel => $msg->{channel},
          body => "Status deleted successfully!"
        );
        return;
      }

      # if poster's not in allowed nicks
    } else {
      $self->say(
        who => $msg->{who},
        channel => $msg->{channel},
        body => "On se connait ?"
      );
      return;
    }
  }

  # shrink links
  # partly form ln-s.net ;) thanks to them
  if ($msg->{body} =~ /^\@shrink\s*(.+)$/) {
    if ($rdb->get($redis_pref.$msg->{who})) {
      # set up the LWP User Agent and create the request
      my $userAgent = new LWP::UserAgent;
      my $request = new HTTP::Request POST => 'http://ln-s.net/home/api.jsp';
      $request->content_type('application/x-www-form-urlencoded');

      # encode the URL and add it to the url parameter in the request
      my $url = $1;
      $url = URI::Escape::uri_escape($url);
      $request->content("url=$url");

      # make the request
      my $response = $userAgent->request($request);

      # handle the response
      if ($response->is_success) {
        my $reply = $response->content;
        1 while(chomp($reply));
        my ($status, $message) = split(/ /,$reply, 2);
        $self->say(
          who => $msg->{who},
          channel => $msg->{channel},
          body => $message
        );
      } else {
        my ($status, $message) = split(/ /,$response->status_line, 2);
        $self->say(
          who => $msg->{who},
          channel => $msg->{channel},
          body => "Erf... Statut : $status => $message"
        );
      }
      return;

    } else {
      $self->say(
        who => $msg->{who},
        channel => $msg->{channel},
        body => "On se connait ?"
      );
      return;
    }
  }
  # little help
  if ($msg->{body} =~ /\@help/) {
    $self->say(
      who => $msg->{who},
      channel => $msg->{channel},
      body => "Je suis un bot qui lie ce canal irc à twitter."
    );

    if ($msg->{who} ~~ $masters) {
      $self->say(
        who => $msg->{who},
        channel => $msg->{channel},
        body => "\@allow [user] pour autoriser [user] à tweeter, \@disallow [user] pour enlever [user] de la liste des tweetants"
      );
    }
    $self->say(
      who => $msg->{who},
      channel => $msg->{channel},
      body => "\@tweet [texte] pour twetter [texte], \@retweet [id] pour retweeter le tweet [id], \@reply [id] [\@user_référencé texte], \@delete [id] pour supprimer le status [id], \@shrink [url] pour racourcir [url]"
    );
  }

  # add an user to the "known nicks" list
  if (($msg->{who} ~~ $masters) and $msg->{body} =~ /\@allow\s*(\w+)/) {
    $rdb->set($redis_pref.$1, 1);
    $self->say(
      who => $msg->{who},
      channel => $msg->{channel},
      body => "Ok ! $1 est maintenant dans la liste des twolls potentiels :3"
    );
  }

  # remove an user from the "known nicks" list
  if (($msg->{who} ~~ $masters) and $msg->{body} =~ /\@disallow\s*(\w+)/) {
    $rdb->del($redis_pref.$1) if $rdb->get($redis_pref.$1);
    $self->say(
      who => $msg->{who},
      channel => $msg->{channel},
      body => "Adieu $1, je l'aimais bien"
    );
  }

#  if ($msg->{body} =~ /https?:\/\/twitter\.com\/[^\/]+\/(\d*)[\/\s]/) {
#	my $tweet = $twlk->show_status($1);
#	$self->say(
#		channel => $msg->{channel},
#		body => $tweet->{user}->{screen_name}." => ".$tweet->{text}." (id: ".$tweet->{id_str}." )"
#	);
#  }
}


# verify twitter mentions every 5 minutes
sub tick {
  my ($self) = @_;

  # twitter link
  my $twlk = Net::Twitter->new(
    traits   => [qw/OAuth API::RESTv1_1/],
	ssl 	 => 1,
    consumer_key        => $self->{consumer_key},
    consumer_secret     => $self->{consumer_secret},
    access_token        => $self->{token},
    access_token_secret => $self->{token_secret}
  );

  # redis link
  my $redis_db = $self->{redis_db};
  my $redis_pref = $self->{redis_pref};

  my $rdb = Redis->new();
  $rdb->select($redis_db);

  # get id of last mention read
  my $last = $rdb->get($redis_pref."last_twid");
  my @statuses;
  if (!$last) {
    @statuses = @{$twlk->mentions()};
  } else {
    @statuses = @{$twlk->mentions({since_id => $last})};
  }


  # send each tweet to the IRC chan
  my $len = scalar(@statuses);
  if ($len > 0) {
    my $status;
    my $i = 1;
    while ($i <= $len) {
      $self->say(
        channel => $self->{channels}->[0],
        body => $statuses[$len-$i]->{user}->{screen_name}." => ".$statuses[$len-$i]->{text}." ( https://twitter.com/".$statuses[$len-$i]->{user}->{screen_name}."/status/".$statuses[$len-$i]->{id_str}." )"
      );
      $i++;
    }

    $rdb->set($redis_pref."last_twid", $statuses[$len+1-$i]->{id});
  }

  # sleep 5 min ;)
  return 5*60;
}

1;
