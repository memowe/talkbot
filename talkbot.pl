#!/usr/bin/env perl

# O HAI.
package TalkBot;
use base 'Bot::BasicBot';

use v5.10.0;
use strict;
use warnings;

use Config::Auto;
use POSIX 'strftime';
use ORLite {
    unicode     => 1,
    file        => 'talkbot.db',
    x_update    => 1,
    create      => sub { shift->do('
        CREATE TABLE message (
            id      INTEGER PRIMARY KEY AUTOINCREMENT,
            channel TEXT,
            nick    TEXT,
            time    INTEGER,
            text    TEXT
        )
    ')},
};

# CAN HAS CONFIGURASHUN?
my $config = Config::Auto::parse;

# message queue (array of hashs with channel and message)
my @queue;

# counter for other peoples messages
my %count = map {$_ => 0} @{$config->{channels}};

# log if verbose
sub talkbot_log {
    my $msg = shift;
    if ($config->{verbose} // 1) {
        my $time = strftime '%Y-%m-%d %H:%M', localtime;
        say "$time $msg";
    }
}

# remember messages from 'said' hashes
sub remember {
    my ($self, $data) = @_;

    # ignore some channels
    if ($data->{channel} ~~ $config->{ignore_channels}) {
        talkbot_log("ignored $data->{channel} ($data->{who})");
        return;
    }

    # delete highlight
    my @local_nicks = keys %{$self->channel_data($data->{channel})};
    $data->{body} =~ s/^\Q$_\E[,:]?\s+(.*)/$1/ for @local_nicks;

    # ignore text with nick names after highlight
    my @nicks = map { keys %{$self->channel_data($_)} } $self->channels;
    foreach my $nick (@nicks) {
        if ($data->{body} =~ /\Q$nick\E/) {
            talkbot_log("ignored $data->{channel} (line contains $nick)");
            return;
        }
    }

    # remember
    my $message = TalkBot::Message->create(
        channel => $data->{channel},
        nick    => $data->{who},
        time    => time,
        text    => $data->{body},
    );

    # log
    (my $short_body = $data->{body}) =~ s/^(.{17}).{3,}/$1.../;
    talkbot_log("in $data->{channel} $data->{who} said: $short_body");
}

# react on messages
sub react {
    my ($self, $data) = @_;
    my @all_messages = TalkBot::Message->select;

    # soon...
    return if @all_messages < $config->{min_messages};

    # count messages on channels
    $count{$data->{channel}}++;

    # react immediately on highlight
    $count{$data->{channel}} = $config->{talk_count_max} if $data->{address};

    # soon...
    return if $count{$data->{channel}} < rand $config->{talk_count_max};

    # choose an old message
    @all_messages   = sort {$a->time <=> $b->time} @all_messages;
    my $max_choose  = @all_messages * $config->{choose_ratio};
    my @messages    = @all_messages[0 .. $max_choose];
    my $message     = $messages[rand @messages];
    my $msg         = $message->text;

    # highlight (sometimes)
    if (rand() < $config->{highlight_ratio}) {
        $msg = "$data->{who}: $msg";
    }

    # add to queue and fire
    my $p_min   = $config->{talk_pause_min};
    my $p_max   = $config->{talk_pause_max};
    my $pause   = $p_min + rand($p_max - $p_min);
    push @queue, {message => $msg, channel => $data->{channel}};
    $self->schedule_tick($pause);

    # reset counter
    $count{$data->{channel}} = 0;

    # reset message time
    $message->update(time => time + $pause);
}

# got a message
sub said {
    my ($self, $data) = @_;

    # don't react on queries
    return if $data->{channel} eq 'msg';

    # don't forget anything
    $self->remember($data);

    # decide what to do
    $self->react($data);

    # nuff said
    return;
}

# actions: do nothing (fires 'said' by default)
sub emoted {}

# send messages from message queue asynchronicaliolly
sub tick {
    my $self = shift;

    # send next message
    my $next = shift @queue;
    return unless defined $next;
    $self->say(
        channel => $next->{channel},
        body    => $next->{message},
    );

    # log
    (my $short = $next->{message}) =~ s/^(.{17}).{3,}/$1.../;
    talkbot_log("in $next->{channel} I said: $short");
}

# generate cool names
sub rand_name {

    # split alphabet characters
    my @vo = qw(a e i o u);
    my @co = grep {not $_ ~~ @vo} 'a' .. 'z';
    my %ch = (a => \@vo, p => \@co);

    # build name by template
    my @templates = @{ $config->{nick_templates} // [qw( papa paap )] };
    my $template  = @templates[rand @templates];
    (my $name = $template) =~ s/./ ${$ch{$&}}[rand @{$ch{$&}}] /eg;

    return $name;
}

# initialize and run the bot
my $bot = TalkBot->new(
    server      => $config->{server}    // 'irc.quaknet.org',
    channels    => $config->{channels}  // ['#html.de.selbsthilfe'],
    nick        => rand_name(),
    alt_nicks   => [ map {rand_name} 1 .. 100 ],
    username    => rand_name(),
    name        => rand_name(),
)->run;

__END__
