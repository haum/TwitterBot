use TwitterBot;


my $Twaum = TwitterBot->new(
	# twitter
	consumer_key => "",
	consumer_secret => "",
	token => "",
	token_secret => "",
	# Redis
	redis_db => 1,
	redis_pref => "TwitterBot",
	master => "JohnDoe",
	# IRC
	server => "irc.freenode.org",
	port => 7000,
	ssl => 1,
	channels => ["#poney"],
	nick => 'MyTwitterBot'
)->run();
