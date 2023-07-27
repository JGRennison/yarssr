package Yarssr::GUI;

use strict;
use warnings;

use Gtk2;
use Gtk2::GladeXML;
use Gtk2::SimpleList;
use Gtk2::TrayIcon;
use Yarssr::Config;
use Yarssr::Parser;
use Yarssr::Fetcher;
use Yarssr::Browser;
use Data::Dumper;
use POSIX ":sys_wait_h";
use Guard;

use constant TRUE => 1,FALSE => 0;

my $prefs_window;
my $import_dialog;
my $feedinfo_dialog;
my $add_dialog;
my $prop_dialog;
my $gld;
my $menu;
my $pref_menu;
my $icon;
my $eventbox;
my $tooltips;

my $treeview;

my $paper_grey_pixbuf;
my $paper_red_pixbuf;
my $paper_green_pixbuf;
my $dot_full_red_pixbuf;
my $dot_hollow_red_pixbuf;
my $blank_pixbuf;
my $tray_image;

my $activity_refcount = 0;
my $activity_refcount_blocking = 0;

sub init {
	my $class = shift;
	my $cv = shift;

	Gtk2->init;

	my $imagedir = $Yarssr::PREFIX . "/share/yarssr/pixmaps/";

	$paper_grey_pixbuf = Gtk2::Gdk::Pixbuf->new_from_file(
		$imagedir . "paper_grey.xpm");
	$paper_red_pixbuf = Gtk2::Gdk::Pixbuf->new_from_file(
		$imagedir . "paper_red.xpm");
	$paper_green_pixbuf = Gtk2::Gdk::Pixbuf->new_from_file(
		$imagedir . "paper_green.xpm");
	$dot_full_red_pixbuf = Gtk2::Gdk::Pixbuf->new_from_file(
		$imagedir . "full_red.xpm");
	$dot_hollow_red_pixbuf = Gtk2::Gdk::Pixbuf->new_from_file(
		$imagedir . "hollow_red.xpm");
	$blank_pixbuf = Gtk2::Gdk::Pixbuf->new_from_file(
		$imagedir . "blank.xpm");
	$tray_image = Gtk2::Image->new_from_pixbuf(
		$paper_grey_pixbuf);

	$tooltips = Gtk2::Tooltips->new;

	# Create tray inon
	my $tray = Gtk2::TrayIcon->new("rss");
	$eventbox = Gtk2::EventBox->new;

	$eventbox->add($tray_image);
	update_icon_state();

	$tray->add($eventbox);
	$tray->show_all;
	Gtk2->main_iteration while Gtk2->events_pending;

	$gld = Gtk2::GladeXML->new($Yarssr::PREFIX . '/share/yarssr/yarssr.glade');
	$gld->signal_autoconnect_from_package('main');

	$prefs_window = $gld->get_widget('window_prefs');
	$prefs_window->signal_connect('delete-event' => \&delete_event);

	$import_dialog = $gld->get_widget('import_dialog');
	$import_dialog->set_transient_for($prefs_window);
	$import_dialog->signal_connect('delete-event' => \&delete_event);

	$feedinfo_dialog = $gld->get_widget('feed_dialog');
	$feedinfo_dialog->set_transient_for($prefs_window);
	$feedinfo_dialog->signal_connect('delete-event' => \&delete_event);

	$treeview = Gtk2::TreeView->new;
	$treeview->set_rules_hint(1);

	my $icon = Gtk2::TreeViewColumn->new_with_attributes(
		'', Gtk2::CellRendererPixbuf->new, pixbuf => 0);
	my $title = Gtk2::TreeViewColumn->new_with_attributes(
		_("Name"), Gtk2::CellRendererText->new, text => 1);
	my $toggle = Gtk2::CellRendererToggle->new;
	$toggle->set_data( column => 2);
	$toggle->signal_connect(toggled => \&item_toggled);
	my $enabled = Gtk2::TreeViewColumn->new_with_attributes(
		_("Enabled"), $toggle, active => 2);
	$enabled->set_clickable(1);
	$enabled->signal_connect('clicked', \&enabled_header_clicked);
	my $text = Gtk2::CellRendererText->new;
	#$text->set_fixed_size(150,-1);
	my $location = Gtk2::TreeViewColumn->new_with_attributes(
		_("Address"), $text, text => 3);
	for (($icon, $title, $enabled, $location)) {
		$treeview->append_column($_);
	}

	my $scrolledwindow = $gld->get_widget('scrolledwindow_feeds');
	$scrolledwindow->add($treeview);

	create_prefs_menu();

	$cv->send();

	Gtk2->main;
};

sub delete_event {
	$_[0]->hide;
	feedinfo_dialog_clear();
	return 1;
}

sub get_icon_activity_guard {
	$activity_refcount++;
	update_icon_state();
	return guard {
		$activity_refcount--;
		update_icon_state();
	};
}

sub get_icon_activity_blocking_guard {
	$activity_refcount++;
	$activity_refcount_blocking++;
	update_icon_state();
	return guard {
		$activity_refcount--;
		$activity_refcount_blocking--;
		update_icon_state();
	};
}

sub update_icon_state {
	Yarssr->log_debug("update_icon_state: active: $activity_refcount, blocking: $activity_refcount_blocking");
	$eventbox->signal_handlers_disconnect_by_func(\&handle_button_press);
	$eventbox->signal_handlers_disconnect_by_func(\&ignore_button_press);
	$eventbox->signal_connect("button-press-event", ($activity_refcount_blocking > 0) ? \&ignore_button_press : \&handle_button_press);
	if ($activity_refcount > 0) {
		$tray_image->set_from_pixbuf($paper_red_pixbuf);
		set_tooltip(_("updating..."));
	} else {
		my $newitems = Yarssr->get_total_newitems;

		if ($newitems) {
			$tray_image->set_from_pixbuf($paper_green_pixbuf);
		} else {
			$tray_image->set_from_pixbuf($paper_grey_pixbuf);
		}

		set_tooltip($newitems." new links since last update");
	}
}

sub launch_url {
	my $url = shift;

	if (my $child = fork) {
		Glib::Timeout->add(200,
			sub {
				my $kid = waitpid($child, WNOHANG);
				$kid > 0 ? return 0 : return 1;
			}
		);
	} else {
		my $b = Yarssr::Config->get_browser;
		my @b = split(' ', Yarssr::Config->get_browser);
		if (grep(/\%s/, @b)) {
			map { grep(s/\%s/$url/, $_) => $_ } @b;
		} else {
			push(@b, $url);
		}
		exec(@b) or warn "unable to launch browser\n";
		exit;
	}
}

sub prefs_show {
	my $liststore = Gtk2::ListStore->new(
		"Gtk2::Gdk::Pixbuf", #icon
		"Glib::String",      #title
		"Glib::Boolean",     #enabled
		"Glib::String",      #url
		"Glib::String",      #username
		"Glib::String",      #password
		"Glib::Boolean",     #excludenew
	);

	$treeview->set_model($liststore);

	for (Yarssr->get_feeds_array) {
		my $pixbuf = undef;
		if ($_->get_status) {
			my $invis = Gtk2::Invisible->new;
			$pixbuf = $invis->render_icon('gtk-dialog-warning','menu')
		}

		my $iter = $liststore->append;

		$liststore->set($iter,
			0	=> $pixbuf,
			1	=> $_->get_title,
			2	=> $_->get_enabled,
			3	=> $_->get_url,
			4	=> defined $_->get_username ? $_->get_username : 0,
			5	=> defined $_->get_password ? $_->get_password : 0,
			6	=> $_->get_excludenew,
		);
	}

	$gld->get_widget('interval_entry')->set_text(Yarssr::Config->get_interval);
	$gld->get_widget('headings_entry')->set_text(Yarssr::Config->get_maxfeeds);
	$gld->get_widget('browser_entry')->set_text(Yarssr::Config->get_browser);
	$gld->get_widget('start_online_checkbutton')->set_active(
		Yarssr::Config->get_startonline);
	$gld->get_widget('clear_new_on_restart_checkbox')->set_active(
		Yarssr::Config->get_clearnewonrestart);

	$gld->get_widget('pref_ok_button')->grab_focus;

	$prefs_window->show_all;
}

sub item_toggled {
	my ($cell, $path_str) = @_;
	my $liststore = $treeview->get_model;
	my $path = Gtk2::TreePath->new_from_string($path_str);

	my $column = $cell->get_data('column');

	my $iter = $liststore->get_iter($path);
	my $toggled_item = $liststore->get($iter,$column);

	$toggled_item ^= 1;

	$liststore->set($iter, $column, $toggled_item);
}

sub on_pref_cancel_button_clicked {
	$treeview->set_model(undef);

	$prefs_window->hide;
	$feedinfo_dialog->hide;
}

sub on_pref_ok_button_clicked {
	my $liststore = $treeview->get_model;

	$gld->get_widget('pref_ok_button')->signal_handlers_disconnect_by_func(
		\&on_pref_ok_button_clicked);
	$gld->get_widget('pref_cancel_button')->signal_handlers_disconnect_by_func(
		\&on_pref_cancel_button_clicked);

	$prefs_window->hide;
	Gtk2->main_iteration while Gtk2->events_pending;

	my $interval = $gld->get_widget('interval_entry')->get_text;
	my $maxfeeds = $gld->get_widget('headings_entry')->get_text;
	my $browser = $gld->get_widget('browser_entry')->get_text;
	my $online = $gld->get_widget('start_online_checkbutton')->get_active;
	my $clearnewonrestart = $gld->get_widget('clear_new_on_restart_checkbox')->get_active;
	my $usegnome;

	if ($gld->get_widget('use_default_browser_checkbox')->get_active) {
		$usegnome = 1;
	} else {
		$usegnome = 0;
	}

	my $newfeedlist;

	$liststore->foreach(sub {
		my ($model, $path, $iter) = @_;
		my (undef, $title, $enabled, $url, $user, $pass) = $liststore->get($iter);
		$newfeedlist->{$url} = [ $title, $enabled, $user, $pass ];
		return 0;
	});

	my $cv = Yarssr::Config->process(
		$interval, $maxfeeds, $browser, $usegnome, $newfeedlist, $online, $clearnewonrestart);
	$cv->cb(sub {
		redraw_menu() if $cv->recv;
		Yarssr::Config->write_config;
	});

	$treeview->set_model(undef);
}


sub on_use_default_browser_checkbox_toggled {
	my ($widget, $window) = @_;

	my $browser_entry = $gld->get_widget('browser_entry');

	if ($widget->get_active) {
		$browser_entry->set_sensitive(0);
	} else {
		$browser_entry->set_sensitive(1);
	}
}

sub on_add_button_clicked {
	my $ok_button = $gld->get_widget('feedinfo_ok_button');
	$ok_button->signal_handlers_disconnect_by_func(\&properties_change);

	$ok_button->signal_connect('clicked', \&feedinfo_add);

	$feedinfo_dialog->show_all;
}

sub on_remove_button_clicked {
	my @rows = $treeview->get_selection->get_selected_rows;
	my $liststore = $treeview->get_model;
	for (reverse @rows) {
		my $iter = $liststore->get_iter($_);
		$liststore->remove($iter);
	}
}

sub feedinfo_add {
	my $title = $gld->get_widget('feedinfo_name');
	my $url = $gld->get_widget('feedinfo_address');
	my $username = $gld->get_widget('feedinfo_username');
	my $password = $gld->get_widget('feedinfo_password');
	my $excludenew = $gld->get_widget('feedinfo_exclude_new');
	my $ok_button = $gld->get_widget('feedinfo_ok_button');
	my $liststore = $treeview->get_model;

	$ok_button->signal_handlers_disconnect_by_func(\&feedinfo_add);

	unless (Yarssr->get_feed_by_url($url->get_text) or
			Yarssr->get_feed_by_title($title->get_text)) {
		my $iter = $liststore->append;
		$liststore->set($iter,
			0	=> undef,
			1	=> $title->get_text,
			2	=> 1,
			3	=> $url->get_text,
			4	=> $username->get_text,
			5	=> $password->get_text,
			6	=> $excludenew->get_active,
		);
	}

	feedinfo_dialog_clear();
	$feedinfo_dialog->hide;
}

sub feedinfo_dialog_clear {
	$gld->get_widget('feedinfo_name')->set_text('');
	$gld->get_widget('feedinfo_address')->set_text('');
	$gld->get_widget('feedinfo_username')->set_text('');
	$gld->get_widget('feedinfo_password')->set_text('');
	$gld->get_widget('feedinfo_exclude_new')->set_active(0);
	$gld->get_widget('feedinfo_options')->set_expanded(0);
}

sub on_feedinfo_cancel_button_clicked {
	feedinfo_dialog_clear();
	$feedinfo_dialog->hide;
}

sub redraw_menu {
	my $class = shift;
	Yarssr->log_debug(_("Rebuilding menu"));

	for my $feed (Yarssr->get_feeds_array) {
		Gtk2->main_iteration while Gtk2->events_pending;
		create_feed_menu($feed) if $feed->get_enabled;
	}
	create_root_menu();
	update_icon_state();
}

sub create_root_menu {
	$menu = Gtk2::Menu->new;
	my $refresh = Gtk2::ImageMenuItem->new_from_stock('gtk-refresh');
	my $clear_new = Gtk2::ImageMenuItem->new(_("_Unmark new"));
	my $open_new = Gtk2::ImageMenuItem->new(_("_Open new"));
	$clear_new->set_image(Gtk2::Image->new_from_stock('gtk-clear', 'menu'));
	$open_new->set_image(Gtk2::Image->new_from_stock('gtk-dnd-multiple', 'menu'));
	$refresh->signal_connect('activate', sub {
		$menu->popdown;
		Gtk2->main_iteration while Gtk2->events_pending;
		Yarssr->download_all;
	});
	$clear_new->signal_connect('activate', sub {
		Yarssr->clear_newitems;
		redraw_menu();
	});
	$open_new->signal_connect('activate', sub {
		for my $feed (Yarssr->get_feeds_array) {
			foreach my $item ($feed->get_newitems_array) {
				launch_url($item->get_url);
			}
		}
		Yarssr->clear_newitems(1);
		redraw_menu();
	});
	$menu->append($refresh);
	$menu->append($clear_new);
	$menu->append($open_new);

	$menu->append(Gtk2::SeparatorMenuItem->new);

	for my $feed (Yarssr->get_feeds_array) {
		if ($feed->get_enabled) {
			my $title = $feed->get_title;
			my $menuitem = Gtk2::ImageMenuItem->new_with_label($title);
			$menuitem->child->set_markup("<b>$title</b>") if $feed->get_newitems;

			if (defined $feed->get_status and $feed->get_status > 0) {
				my $image = Gtk2::Image->new_from_stock('gtk-dialog-warning', 'menu');
				$menuitem->set_image($image);
			} elsif (my $icon = $feed->get_icon) {
				my $image = Gtk2::Image->new_from_pixbuf($icon);
				$menuitem->set_image($image);
			}

			$menuitem->set_submenu($feed->get_menu);
			$menu->append($menuitem);
		}
	}
	$menu->show_all;
	return $menu;
}

sub create_prefs_menu {
	$pref_menu = Gtk2::Menu->new;
	my $quit = Gtk2::ImageMenuItem->new_from_stock('gtk-quit');
	my $prefs = Gtk2::ImageMenuItem->new_from_stock('gtk-preferences');

	my $online;
	my $imageroot = $Yarssr::PREFIX . "/share/yarssr/pixmaps/";

	if (Yarssr::Config->get_online) {
		$online = Gtk2::ImageMenuItem->new(_("Go _Offline"));
		my $image = Gtk2::Image->new_from_file($imageroot . "disconnect.png");
		$online->set_image($image);
		$online->signal_connect('activate',
			sub { Yarssr::Config->set_online(0); create_prefs_menu(); });

	}
	else {
		$online = Gtk2::ImageMenuItem->new(_("Go _Online"));
		my $image = Gtk2::Image->new_from_file($imageroot . "connect.png");
		$online->set_image($image);
		$online->signal_connect('activate',
			sub { Yarssr::Config->set_online(1); create_prefs_menu(); });
	}

	$prefs->signal_connect('activate', \&prefs_show);
	$quit->signal_connect('activate', sub {
		Yarssr::Config->write_config;
		Yarssr::Config->write_states;
		Glib::Idle->add(sub {
			quit();
			exit;
		});
	});
	$pref_menu->append($online);
	$pref_menu->append($prefs);
	$pref_menu->append($quit);
	$pref_menu->show_all;
	return $pref_menu;
}

sub create_feed_menu {
	my $feed = shift;
	$feed->new_menu;
	my $feedcounter = 0;
	my $image;
	$feed->reset_newitems;
	foreach my $item ($feed->get_items_array) {
		Gtk2->main_iteration while Gtk2->events_pending;
		last if $feedcounter == Yarssr::Config->get_maxfeeds;
		$feedcounter++;

		# Clean up the title for the menu
		my $title;
		$title = $item->get_title or $title = '-no title-';
		$title =~ s/\n//g;
		$title =~ s/(?:\s+|\t+)/ /g;
		my @title = split /(.{42}.+?)\s/, $title;
		shift @title if $title[0] eq '';
		$title = shift @title;
		foreach (@title) {
			next if $_ eq '';
			$title .= "\n";
			$title .= $_;
		}

		my $menuitem = Gtk2::ImageMenuItem->new_with_label($title);
		my $status = $item->get_status;

		if ($status == 4 or $status == 3) {
			$image = Gtk2::Image->new_from_pixbuf(
				$dot_full_red_pixbuf);
			$menuitem->set_image($image);
			$item->set_status(3);
			$feed->add_newitem;
		}
		elsif ($status == 2) {
			$image = Gtk2::Image->new_from_pixbuf(
			$dot_hollow_red_pixbuf);
			$menuitem->set_image($image);
		}
		else {
			$image = Gtk2::Image->new_from_pixbuf(
				$blank_pixbuf);
			$item->set_status(1);
			$menuitem->set_image($image);
		}
		$menuitem->signal_connect('activate', sub {
				menuitem_clicked($menuitem,$item);
			});
		$feed->get_menu->append($menuitem);
	}
	$feed->get_menu->append(Gtk2::SeparatorMenuItem->new);
	my $update = Gtk2::ImageMenuItem->new(_("Update this feed"));
	$update->set_image(Gtk2::Image->new_from_stock('gtk-refresh', 'menu'));
	$update->signal_connect('activate', sub {
			Yarssr->download_feed($feed);
		});
	$feed->get_menu->append($update);
	my $unmark = Gtk2::ImageMenuItem->new(_("Unmark new"));
	$unmark->set_image(Gtk2::Image->new_from_stock('gtk-clear', 'menu'));
	$unmark->signal_connect('activate', sub {
			Yarssr->clear_newitems_in_feed($feed);
			redraw_menu();
		});
	$feed->get_menu->append($unmark);
	my $open_new = Gtk2::ImageMenuItem->new(_("_Open new"));
	$open_new->set_image(Gtk2::Image->new_from_stock('gtk-dnd-multiple', 'menu'));
	$open_new->signal_connect('activate', sub {
			foreach my $item ($feed->get_newitems_array) {
				launch_url($item->get_url);
			}
			Yarssr->clear_newitems_in_feed($feed, 1);
			redraw_menu();
		});
	$feed->get_menu->append($open_new);
	$feed->get_menu->show_all;
}

sub menuitem_clicked {
	my $menuitem = shift;
	my $item = shift;

	launch_url($item->get_url);

	my $feed = $item->get_parent;
	my $status = $item->get_status;

	unless ($status == 1) {
		Glib::Idle->add(sub {
				Yarssr::Config->write_state($feed);
			});
	}

	my $newitems;
	if ($status > 2) {
		$newitems = $feed->subtract_newitem();
	}

	$item->set_status(1);
	redraw_menu() unless $newitems;

	set_tooltip(Yarssr->get_total_newitems." new links since last update");

	my $image = Gtk2::Image->new_from_pixbuf($blank_pixbuf);
	$menuitem->set_image($image);
}

sub get_menu {
	return $menu->{menu};
}

sub ignore_button_press {
	Yarssr->log_debug("Menu is disabled while updating");
	return 1;
}

sub handle_button_press {
	my $widget = shift;
	my $event = shift;

	my $menu_x = $event->x_root - $event->x;
	my $menu_y = $event->y_root - $event->y;
	my $m = ($event->button == 1) ? $menu : $pref_menu;
	my $handler = sub {
		return position_menu($m, $menu_x, $menu_y);
	};
	$m->popup(undef, undef, $handler, 0, $event->button, $event->time);
}

sub position_menu {
	my ($menu, $x, $y) = @_;
	# Shamlessly stolen from Muine :-)

	my $monitor = $menu->get_screen->get_monitor_at_point($x, $y);
	my $rect = $menu->get_screen->get_monitor_geometry($monitor);

	my $space_above = $y - $rect->y;
	my $space_below = $rect->y + $rect->height - $y;

	my $requisition = $menu->size_request();

	if ($requisition->height <= $space_above || $requisition->height <= $space_below) {
		if ($requisition->height <= $space_below) {
			$y = $y + $eventbox->allocation->height;
		} else {
			$y = $y - $requisition->height;
		}
	} elsif ($requisition->height > $space_below and $requisition->height > $space_above) {
		if ($space_below >= $space_above) {
			$y = $rect->y + $rect->height - $requisition->height;
		} else {
			$y = $rect->y;
		}
	} else {
		$y = $rect->y;
	}
	return ($x, $y, 1);
}

sub gui_update {
	Gtk2->main_iteration while Gtk2->events_pending;
}

sub on_properties_button_clicked {
	my @paths = $treeview->get_selection->get_selected_rows;
	return unless @paths;

	my $liststore = $treeview->get_model;

	my $iter = $liststore->get_iter($paths[0]);
	my @row = $liststore->get($iter);

	$gld->get_widget('feedinfo_name')->set_text($row[1]);
	$gld->get_widget('feedinfo_address')->set_text($row[3]);
	$gld->get_widget('feedinfo_username')->set_text($row[4]);
	$gld->get_widget('feedinfo_password')->set_text($row[5]);
	$gld->get_widget('feedinfo_exclude_new')->set_active($row[6]);


	my $ok_button = $gld->get_widget('feedinfo_ok_button');

	$ok_button->signal_handlers_disconnect_by_func(\&feedinfo_add);

	$ok_button->signal_connect('clicked', \&properties_change,$paths[0]);

	$feedinfo_dialog->show_all;
}

sub properties_change {
	my (undef, $path) = @_;

	my $liststore = $treeview->get_model;
	my $iter = $liststore->get_iter($path);
	my @row = $liststore->get($iter);

	my $feed = Yarssr->get_feed_by_url($row[3]);
	my $ok_button = $gld->get_widget('feedinfo_ok_button');

	$ok_button->signal_handlers_disconnect_by_func(\&properties_change);
	$feedinfo_dialog->hide;

	my $new_title = $gld->get_widget('feedinfo_name')->get_text;
	my $new_url = $gld->get_widget('feedinfo_address')->get_text;
	my $new_username = $gld->get_widget('feedinfo_username')->get_text;
	my $new_password = $gld->get_widget('feedinfo_password')->get_text;
	my $new_excludenew = $gld->get_widget('feedinfo_exclude_new')->get_active;

	$liststore->set($iter,
		1	=> $new_title,
		3	=> $new_url,
		4	=> $new_username,
		5	=> $new_password,
		6	=> $new_excludenew,
	);

	# Need to figure out some way to apply this only when
	# the user clicks Ok.
	if ($feed) {
		$feed->set_title($new_title);
		$feed->set_url($new_url);
		$feed->set_username($new_username);
		$feed->set_password($new_password);
		$feed->enable_and_flag if $feed->get_enabled;
		$feed->set_excludenew($new_excludenew);
	}

	feedinfo_dialog_clear();
}

sub enabled_header_clicked {
	my $liststore = $treeview->get_model;
	my $total = $liststore->iter_n_children;
	my $enabled = 0;
	$liststore->foreach(sub { $enabled += $_[0]->get($_[2], 2); 0; });

	my $bool = 1;
	$bool = 0 if $total == $enabled;

	$liststore->foreach(sub { $_[0]->set($_[2], 2, $bool); 0; });
}

sub set_tooltip {
	my $text = shift;
	$tooltips->set_tip($eventbox,$text);
}

sub quit {
	Gtk2->main_quit;
}

sub on_import_button_clicked {
	my $widget = shift;
	$import_dialog->show_all;
}

sub on_import_ok_button_clicked {
	my $widget = shift;
	my $url = $gld->get_widget('import_url_entry')->get_text;
	my $activity_guard = Yarssr::GUI->get_icon_activity_blocking_guard();
	my $info = Yarssr::Fetcher->fetch_opml($url)->recv; # do a blocking receive, for convenience
	undef $activity_guard;
	my $feeds = Yarssr::Parser->parse_opml($info->{content});
	my $model = $treeview->get_model;
	for (@{ $feeds }) {
		my $iter = $model->append;
		$model->set($iter,
			0 => undef,
			1 => $_->{title},
			2 => 1,
			3 => $_->{url},
		);
	}
	close_import_dialog();
}

sub close_import_dialog {
	$gld->get_widget('import_url_entry')->set_text('');
	$import_dialog->hide;
}

sub on_import_path_button_clicked {
	my $chooser = Gtk2::FileChooserDialog->new("OPML File", $import_dialog, 'open',
		'gtk-cancel'	=> 'cancel',
		'gtk-ok'		=> 'ok',
	);

	my $filter = Gtk2::FileFilter->new;
	$filter->add_pattern('*.xml');
	$filter->add_pattern('*.rdf');
	$filter->add_pattern('*.opml');
	$filter->set_name('OPML Files');

	my $filter2 = Gtk2::FileFilter->new;
	$filter2->add_pattern('*.*');
	$filter2->set_name('All Files');

	$chooser->add_filter($filter);
	$chooser->add_filter($filter2);
	if ('ok' eq $chooser->run) {
		my $uri = $chooser->get_uri;
		$gld->get_widget('import_url_entry')->set_text($uri);
	}
	$chooser->destroy;
}

1;

