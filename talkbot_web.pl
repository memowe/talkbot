#!/usr/bin/env perl
use Mojolicious::Lite;

use FindBin '$Bin';
use POSIX 'strftime';
use Config::Auto;
use ORLite {
    file    => "$Bin/talkbot.db",
    unicode => 1,
};

# CAN HAS CONFIFURASHUN?
my $config = Config::Auto::parse("$Bin/talkbot.config");

# publish $config
helper config => sub { shift; @_ ? $config->{$_[0]} : $config };

# better readability for message timestamps
helper nice_time => sub { strftime '%Y-%m-%d %H:%M', localtime $_[1]->time };

# need basic auth for deletion
plugin 'BasicAuth';

get '/' => sub {
    my $self = shift;

    # get next lines
    my $total       = Message->count;
    my $limit       = int($self->config('choose_ratio') * $total);
    my @next_msgs   = Message->select('order by time limit ?', $limit);

    $self->render(
        messages    => \@next_msgs,
        template    => 'messages',
        next_only   => 1,
    );
} => 'next_messages';

get '/all' => sub {
    my $self = shift;

    # get all lines
    my @messages    = Message->select('order by time');
    my $limit       = int($self->config('choose_ratio') * @messages);

    $self->render(
        messages    => \@messages,
        limit       => $limit,
    );
} => 'messages';

# admins only from here
under sub {
    my $self = shift;
    return unless $self->basic_auth(
        'DELESHUN',
        $self->config('web_username'),
        $self->config('web_password'),
    );
    return 1;
};

post '/delete' => sub {
    my $self = shift;

    # get everything
    my @messages = Message->select;
    
    # delete selected messages
    foreach my $message (@messages) {
        my $param   = 'X' . $message->id;
        my $delete  = $self->param($param);
        $message->delete if defined $delete and $delete eq '1';
    }

    # done
    $self->redirect_to('next_messages');
} => 'delete';

app->start;
__DATA__

@@ messages.html.ep
<!DOCTYPE html>
<html>
<head>
<title>TalkBot Messages</title>
<style type="text/css">
caption { font-size: 1.2em; font-weight: bold; margin: 1em 0 }
th, td { padding: .4em .7em; background-color: white; color: black; }
tr:nth-child(2n) td { background-color: #eee }
th { background-color: #222; color: #eee; text-align: left }
th:first-child { text-align: right }
td.delete { text-align: center }
</style>
</head>
<body>
<h1>TalkBot</h1>

<form action="<%= url_for 'delete' %>" method="post">
<table>
<caption><%= stash('next_only') ? 'next possible ' : '' %>messages</caption>
<thead><tr>
    <th>id</th>
    <th>delete</th>
    <th>last time</th>
    <th>text</th>
</tr></thead>
<tbody>
% foreach my $message (@$messages) {
%   (my $nice_message_time = nice_time $message) =~ s/ /&nbsp;/g;
    <tr>
        <th class="id"><%= $message->id %></th>
        <td class="delete">
            <input type="checkbox" name="X<%= $message->id %>" value="1">
        </td>
        <td class="time"><%== $nice_message_time %></td>
        <td class="text"><%= $message->text %></td>
    </tr>
% }
</tbody>
</table>
<p><a href="<%= url_for stash('next_only') ? 'messages' : 'next_messages' %>">
    <%= stash('next_only') ? 'more' : 'less' %>
</a></p>
<p><input type="submit" value="delete checked lines"></p>
</form>

</body>
</html>
