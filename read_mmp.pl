#!/usr/bin/perl -w

use warnings;
use strict;

use Encode qw{from_to};
use File::Format::RIFF;
use Getopt::Long;

my $show_track_marker_debug = 0;

GetOptions(
    'show-track-marker-debug|stmd'  => \$show_track_marker_debug,
);

my %mix_type = (1 => "Standard mix", 2 => "Beat mix");

my $filename = shift;
my $track_no = 0;
my @tracks = ();

open my $fh, '<', $filename or die "Could not open file: $!";
my ( $riff1 ) = File::Format::RIFF->read( $fh );
close( $fh );
#$riff1->dump;
foreach my $chunk ($riff1->data) {
    #print $chunk->id;
    #print ": ", $chunk->type if ($chunk->id eq 'LIST');
    #print "\n";
    if ($chunk->id eq 'LIST') {
        my $chtype = $chunk->type;
        if ($chtype eq 'TRKL') {
            read_tracklist($chunk);
        } elsif ($chtype eq 'GLBL') {
            read_global($chunk);
        } elsif ($chtype eq 'VIDL') {
            print "MMP file: got video list - unhandled.\n";
        } elsif ($chtype eq 'TRKS') {
            print "TRKS in main data!\n";
            process_TRKS($chunk)
        } else {
            print "MMP file: got unknown chunk type '", $chunk->type, "' id '", $chunk->id, "'\n";
        }
    }
}
print "*** Finishing up ***\n";
print "Tracks: @tracks\n";

sub hexprint {
    my ($data) = @_;
    return join(' ', unpack("(H4)*", $data));
}

sub convert_time {
    my ($timemicros) = @_;
    if (wantarray) {
        return (int($timemicros / 60_000_000), int(($timemicros / 1_000_000) % 60), $timemicros % 1_000_000);
    } else {
        return ($timemicros / 1_000_000);
    }
}

sub string_time {
    my ($timemicros) = @_;
    my $sign = '+';
    if ($timemicros < 0) {
        $sign = '-';
        $timemicros = -$timemicros;
    }
    my ($min, $sec, $frac) = convert_time($timemicros);
    # return sprintf("%s%d (%s%02d:%02d.%06d)", $sign, $timemicros, $sign, $min, $sec, $frac);
    return sprintf("%s%02d:%02d.%06d", $sign, $min, $sec, $frac);
}

sub read_global {
    my ($global) = @_;
    foreach my $item ($global->data) {
        print $item->id, ": ", hexprint($item->data), "\n";
    }
}

sub read_tracklist {
    my ($tracklist) = @_;
    foreach my $track ($tracklist->data) {
        #print "track: ", $track->type, "\n";
        if ($track->type eq 'TRKI') {
            read_track($track);
        } else {
            print "Track list: got unknown data type '", $track->type, "', id '", $track->id, "'\n";
        }
    }
}

sub process_TRKS {
    my ($data) = @_;
    my %track_type = (1 => "Standard track", 2 => "Overlay track");
    print 'Track TRKS: ', hexprint($data), "\n";
    # TRKS: 2000 0000 0100 0000 0a9b 7f05 0000 0000 f8fc 4a23 0000 0000 0a9b 7f05 0000 0000
    my ($vers, $type_no, $start_1, $end, $start_2) = unpack("llqqq", $data);
    print "Warning: TRKS version not 32, was $vers\n" if $vers != 32;
    my $trk_type = (exists $track_type{$type_no}) ? $track_type{$type_no} : "unknown track type ($type_no)";
    return { 'type' => $trk_type, 'start_1' => $start_1, 'start_2' => $start_2, 'end' => $end} ;
}

sub read_track {
    $track_no ++;
    print "New track: $track_no\n";
    my ($track) = @_;
    my %track;
    my ($name);
    my ($trk_type, $mix_type, $start_1, $start_2, $end, $markers, $bpm, $key_adj, $beat_blend);
    foreach my $item ($track->data) {
        my $itemid = $item->id;
        if ($itemid eq 'LIST') {
            if ($item->type eq 'TKLY') {
                #read_track_markers($item);
                $markers = $item;
            } else {
                $item->dump;
            }
        } elsif ($itemid eq 'TRKH') {
            print "Track header: ", hexprint($item->data), "\n";
            my @data = unpack("V*", $item->data);
            #Track header: 2800 0000 0000 0000 0ee6 a0c6 3528 6f1c 5f1b d445 564d e8ee 37c1 0100 0000 0000 0000 0100 0200 0000
            print "Odd - track header pos 0 is $data[0], not 0x28\n" unless $data[0] == 0x28;
            print "Odd - track header pos 1 is $data[1], not 0x00\n" unless $data[1] == 0;
            # next 18 bytes - MD5sum?  some kind of identifier?
            # 3254 = archive key.
            print "Odd - track header pos 7 is $data[7], not 0x00\n" unless $data[7] == 0;
            print "Odd - track header pos 8 is $data[8], not 0x10000\n" unless $data[8] == 0x10000;
            # Position nine is type of track - 1 = standard, 2 = beat mix.
            if (exists $mix_type{$data[9]}) {
                $mix_type = $mix_type{$data[9]};
            } else {
                $mix_type = "unknown mix type ($data[9])";
            }
            # Position 6 is original track BPM * 1000
            $bpm = ($data[6] + 0.0) / 1000;
            # Position 10 is key adjustment up/down
            if (scalar(@data) > 10) {
                $key_adj = ($data[10] + 0.0) / 100;
            } else {
                $key_adj = 0.0;
            }
            # Position 11 is beat blend type (?)
            if (scalar(@data) > 11) {
                $beat_blend = $data[11];
            } else {
                $beat_blend = 0;
            }
        } elsif ($itemid eq 'TRKF') {
            $name = $item->data;
            from_to($name, 'UTF16-le', 'UTF8');
            $name =~ tr{\0}{}d;
            print "File name: $name\n";
        } elsif ($itemid eq 'TRKS') {
            print 'Track TRKS: ', hexprint($item->data), "\n";
#            # TRKS: 2000 0000 0100 0000 0a9b 7f05 0000 0000 f8fc 4a23 0000 0000 0a9b 7f05 0000 0000
#            my ($d0, $type_no);
#            ($d0, $type_no, $start_1, $end, $start_2) = unpack("llqqq", $item->data);
#            #printf "Track start: %s or %s; end: %s\n", string_time($data[2]), string_time($data[6]), string_time($data[4]);
#            print "Warning: TRKS field 1 not 32, was $d0\n" if $d0 != 32;
#            if (exists $track_type{$type_no}) {
#                $trk_type = $track_type{$type_no};
#            } else {
#                $trk_type = "unknown track type ($type_no)"
#            }
            my $href = process_TRKS($item->data);
            ($trk_type, $start_1, $end, $start_2) = @{ $href }{qw{ type start_1 end start_2 }};
        } elsif ($itemid eq 'TRKM') {
# We ignore them here, since we read them in read_track_markers()
        } else {
            print "Track data: got unknown id '$itemid':", hexprint($item->data), "\n";
        }
    }
#print "File name: $track{'filename'}\n";
    printf "Track type: %s, %s - %03.2f BPM\n", $mix_type, $trk_type, $bpm;
    printf "*** Track start: %s or %s\n", string_time($start_1), string_time($start_2);
    my $marker_data = read_track_markers($markers);
    printf "*** Track end: %s\n", string_time($end);

    push @tracks, {
        "order" => $track_no,
        "name" => $name,
        "start" => $start_1,
        "end" => $end,
        "markers" => $marker_data,
    }
}

sub compare_markers {
    my @field_order = (2,1,3,4,0,5,6,7);
    # Compare two markers by their 32-bit fields.
    my @a = unpack("V*", $a->data);
    my @b = unpack("V*", $b->data);
    my $i = 0;
    while ($i < scalar @a and $i < scalar @b) {
        my $field = $field_order[$i];
        my $cmp = $a[$field] <=> $b[$field];
        return $cmp if $cmp != 0;
        $i++;
    }
    print "Warning: comparison of part $i fell off end of array for $a->data <=> $b->data\n";
    return 0;
}

sub read_track_markers {
    my ($markers) = @_;
    my @markers;
    # The order in file is variable, but we need to be able to compare markers
    # efficiently.  So we need to sort the markers.  Do this by 32-bit fields.
    # Some of these are also sublists, so we need to process them separately.
    my @sublists;
    foreach my $marker ($markers->data) {
        if ($marker->id eq 'LIST') {
            push @sublists, $marker;
        } else {
            push @markers, $marker;
        }
    }
    foreach my $sublist (@sublists) {
        print "Sublist: ", $sublist->id, ": ", hexprint($sublist->data), "\n";
    }
    my @marker_data;
    foreach my $marker (sort compare_markers @markers) {
        push @marker_data, read_track_marker($marker);
    }
    print "Returned marker data @marker_data\n";
    return \@marker_data;
}

sub interpret_track_marker {
    # Help from https://github.com/liesen/CueMeister/blob/master/src/mixmeister/mmp/Marker.java
    my %type_marker_is = (
    # Have to convert to string because of hash stringification
        '00000001'  => "Intro mk",
        '00000002'  => "Outro mk",
        '00000004'  => "Beat  mk",
        '00000010'  => "Vol frst",
        '00000020'  => "Vol in 1",
        '00000040'  => "Vol in 2",
        '00000200'  => "Vol out1",
        '00000400'  => "Vol out2",
        '00000800'  => "Volume??",
        '00001000'  => "Vol last",
        '00008000'  => "Vol User",
        '00010000'  => "TrebledB",
        '00040000'  => "Bass  dB",
        '00100000'  => "BPM in 1",
        '00200000'  => "BPM in 2",
        '00400000'  => "BPM out3",
        '00800000'  => "BPM out4",
        '01000000'  => "BPM User",
        '04000000'  => "Label   ",
        '08000000'  => "LablUser",
        '10000000'  => "Measure ",
    );
    my ($type, $val) = @_;
    my $type_lu = sprintf('%08x', $type);
    my $typename = $type_marker_is{$type_lu} || $type_lu;
    my $val_format = '  %8d';
    # Val at this stage is a signed integer - needs to be floating point.
    $val = $val + 0.0;
    # Now do scale conversions if necessary
    if ($type & 0x00059E70) {
        # Volume marker of some sort - convert milliBels to deciBels
        $val /= 100;
        $val_format = '%+06.2f dB ';
    } elsif ($type & 0x00f00000) {
        # BPM marker - value is BPM * 1000
        $val /= 1000;
        $val_format = '%06.2f BPM'
    }
    return sprintf "%8s ($val_format)", $typename, $val;
}

sub read_track_marker {
    my ($marker) = @_;
    if ($show_track_marker_debug) {
        print 'Marker ', $marker->id, ": ", hexprint($marker->data), "\n";
    }
    if ($marker->id eq 'TRKS') {
        print "TRKS block inside track markers!\n";
        print "TRKS data:", hexprint($marker->data), "\n";
    }
    unless ($marker->id eq 'TRKM') {
        print "Track markers: Unknown id '", $marker->id, "': ", hexprint($marker->data), "\n";
        return;
    }
    my ($head, $type, $pos, $d, $placer, $val, $g, $h) = unpack("VVlVVlVV", $marker->data);
    print "Odd - track marker header is $head, not 0x20\n" unless $head == 0x20;
    my $marker_type = interpret_track_marker($type, $val);
    my $placer_type = ($placer == 1 ? 'USER' : ($placer == 0 ? 'mixm' : "UNKNOWN PLACER"));
    printf "Pos %16s: Type = %s (%d, %d, %d) %s\n", string_time($pos), $marker_type, $d, $g, $h, $placer_type;
    return {
        "marker" => $marker->id,
        "pos" => $pos,
        "type" => $type,
        "type_interp" => $marker_type,
        "placer" => $placer_type,
        "val1" => $d,
        "val2" => $g,
        "val3" => $h,
    };
}

#my ( $riff2 ) = new File::Format::RIFF( 'TYPE' );
#foreach my $chunk ( $riff1->data ) {
#    next if ( $chunk->id eq 'LIST' );
#    $riff2->addChunk( $chunk->id, $chunk->data );
#}

