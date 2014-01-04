package TwitterBot;

use utf8;
use strict;
use warnings;
use 5.010;
use LWP::UserAgent; # to shrink links
use Bot::BasicBot;
use Net::Twitter;
use Redis; 			# for authorizations

# this class is now a bot !
use base qw( Bot::BasicBot );

# process other's messages
sub said {
  my ($self, $msg) = @_;

  return unless $msg->{body} =~ /^\@/;

  # twitter link
  my $twlk = Net::Twitter->new(
    traits   => [qw/OAuth API::RESTv1_1/],
    consumer_key        => $self->{consumer_key},
    consumer_secret     => $self->{consumer_secret},
    access_token        => $self->{token},
    access_token_secret => $self->{token_secret}
  );

  # redis link
  my $redis_db = $self->{redis_db};
  my $redis_pref = $self->{redis_pref};
  my $master = $self->{master};

  my $rdb = Redis->new();
  $rdb->select($redis_db);


  # if it's from a known nick and the length is OK...
  if ($msg->{body} =~ /^\@tweet (.+)$/) {
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
      $twlk->update($1);
      $self->say(
        who => $msg->{who},
        channel => $msg->{channel},
        body => "C'est parti !"
      );
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
  if ($msg->{body} =~ /^\@retweet (\d+)$/) {
    if ($rdb->get($redis_pref.$msg->{who})) {

      # update twitter account...
      eval { $twlk->retweet($1); };
      if ( $@ ) {
        $self->say(
          who => $msg->{who},
          channel => $msg->{channel},
          body => "Ooops... un petit souci... [ ".$@->error." ]",
          body => "ping ".$master
        );
        return;
      } else {
        $self->say(
          who => $msg->{who},
          channel => $msg->{channel},
          body => "Retweet done !"
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
  if ($msg->{body} =~ /^\@reply (\d+) (.+)$/)
  {
    utf8::encode($2) if(! utf8::is_utf8($2));
    if ($rdb->get($redis_pref.$msg->{who})) {
      if (length($2) > 140) {
        $self->say(
          who => $msg->{who},
          channel => $msg->{channel},
          body => "Un peu long, ".length($1)." au lieu de 140..."
        );
        return;
      }

      # update twitter account...
      $twlk->update($2,{in_reply_to_status_id => $1});
      $self->say(
        who => $msg->{who},
        channel => $msg->{channel},
        body => "C'est parti !"
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
  if ($msg->{body} =~ /^\@delete (\d+)$/) {
    if ($rdb->get($redis_pref.$msg->{who})) {

      # update twitter account...
      eval { $twlk->destroy_status($1); };
      if ( $@ ) {
        $self->say(
          who => $msg->{who},
          channel => $msg->{channel},
          body => "Ooops... un petit souci... [ ".$@->error." ]",
          body => "ping ".$master
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
  if ($msg->{body} =~ /^\@shrink (.+)$/) {
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

    if ($msg->{who} eq $master) {
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
  if (($msg->{who} eq $master) and $msg->{body} =~ /\@allow (\w+)/) {
    $rdb->set($redis_pref.$1, 1);
    $self->say(
      who => $master,
      channel => $msg->{channel},
      body => "Ok ! $1 est maintenant dans la liste des twolls potentiels :3"
    );
  }

  # remove an user from the "known nicks" list
  if (($msg->{who} eq $master) and $msg->{body} =~ /\@disallow (\w+)/) {
    $rdb->del($redis_pref.$1) if $rdb->get($redis_pref.$1);
    $self->say(
      who => $master,
      channel => $msg->{channel},
      body => "Adieu $1, je l'aimais bien"
    );
  }
}


# verify twitter mentions every 5 minutes
sub tick {
  my ($self) = @_;

  # twitter link
  my $twlk = Net::Twitter->new(
    traits   => [qw/OAuth API::REST/],
    consumer_key        => $self->{consumer_key},
    consumer_secret     => $self->{consumer_secret},
    access_token        => $self->{token},
    access_token_secret => $self->{token_secret}
  );

  # redis link
  my $redis_db = $self->{redis_db};
  my $redis_pref = $self->{redis_pref};
  my $master = $self->{master};

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
        body => $statuses[$len-$i]->{user}->{screen_name}." => ".$statuses[$len-$i]->{text}." (#".$statuses[$len-$i]->{id_str}.")"
      );
      $i++;
    }

    $rdb->set($redis_pref."last_twid", $statuses[$len+1-$i]->{id});
  }

  # sleep 5 min ;)
  return 5*60;
}

1;
