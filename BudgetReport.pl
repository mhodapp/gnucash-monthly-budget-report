#!/usr/bin/env perl

#!/usr/bin/perl

use warnings;
use strict;

use Data::Dumper;
use Getopt::Long;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError) ;
use XML::Parser;
use XML::Simple;

########################################################################
# Function: Print Monthly Budget Report.
########################################################################

my %budget_summary;
my $budget_year = 2009;
#my $ig = 0;
#my @ignore_account;
my @month_names = (
    "January", "February", "March",     "April",   "May",      "June",
    "July",    "August",   "September", "October", "November", "December"
);
my @month_abbreviations = (
    "JAN", "FEB", "MAR", "APR", "MAY", "JUN",
    "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"
);
( my $program_name = $0 ) =~ s{.*/}{};
my $uid = getlogin;

my $GNUCash_file = "/home/" . $uid . "/" . $budget_year . "GNUCash.xml";
my $report_file  = "/home/" . $uid . "/BudRep.txt.";

##########################################################################################################################
sub clean_string {    # Clean up string fields.
    $_[0] =~ s/^\s*//;     # remove 0 or more leading spaces.
    $_[0] =~ s/\s*\n?$//;    # remove 0 or more trailing spaces, any 0 or 1 trailing newline.
    $_[0] =~
      s/\s\s+/ /;    # convert any string of 1 or more spaces to a single space.
}

##########################################################################################################################
sub sum_in_split {
    my ( $split, $act_ref ) = @_;
    return unless defined $split->{'split:value'};
    if ( $split->{'split:value'} !~ m{^-?\d+/100$} ) {
        warn "FUNNY value: '$split->{'split:value'}'\n";
    }
    my $value = eval $split->{'split:value'};

    if ( defined $value ) {
        $value = sprintf "%.2f", $value;
        $act_ref->{ $split->{'split:account'}{content} }{total} += $value;
    }
    else {
        warn Dumper $split;
        return;
    }
    return 1;
}

##########################################################################################################################
sub value_in_split {
    my ($split) = @_;
    return unless defined $split->{'split:value'};
    if ( $split->{'split:value'} !~ m{^-?\d+/100$} ) {
        warn "FUNNY value: '$split->{'split:value'}'\n";
    }
    my $value = eval $split->{'split:value'};

    if ( defined $value ) {
        $value = sprintf "%.2f", $value;
    }
    else {
        warn Dumper $split;
        return;
    }
    return $value;
}

##########################################################################################################################
sub usage {
    print <<END_USAGE;

	Usage:
	$program_name [--conf=configuration-file-name] [--debug] [--list] month-abbreviation

		--conf\t- defaults to budrep.conf
	
		--list\t- list accounts suitable for inclusion in configuration file
 
		month-abbreviation (or number), e.g., sep (or 9)

END_USAGE
    exit 1;
}

##########################################################################################################################

##########################################################################################################################

my ( $first_day_report_month, $first_day_next_month, $debug_option, $list_accounts_option, $conf_file );

GetOptions(
    list             => \$list_accounts_option,
    debug            => \$debug_option,
    'conf:s'         => \$conf_file,
) or usage;

########################################################################
# 1: Process command line options
########################################################################

########################################################################
# 1:1 Get configuration file parameters:
########################################################################
if ( !$conf_file ) { $conf_file = "budrep.conf"; }

#print "\t", '$conf_file', " = |$conf_file|\n";

if ( !-e $conf_file ) {    #File?
    print "\tConfiguration file $conf_file does not exist\n";
    usage;
}

open( INPUT, "<$conf_file" ) ||    #open returns true or false
  die "\tCan't input $conf_file $!";
my $GNUCash_account;
my $line_number = 0;

# Set up report separation entries in the report hash.
$budget_summary{"Expenses"} = [ "Expenses", 0, 0, 0, 0 ];
$budget_summary{"Income"} = [ "Income", 0, 0, 0, 0 ];

while (<INPUT>) {
    chop $_;
    ++$line_number;
    ( my $keyword, my $parm ) = split /=/, $_, 3;
    if ($keyword) { clean_string $keyword; }
    if ($parm)    { clean_string $parm; }
    if ( !$keyword ) {
        if ( !$parm ) { next; }    #Empty line
        else {
            print "\tNo keyword, line $line_number in $conf_file ignored!\n";
            next;
        }
    }
    if ( "#" eq substr( $keyword, 0, 1 ) ) {
        next;
    }    # 1st non-blank character is "#"
    if ( !$parm ) {
        print
"\tNo parameter for keyword $keyword, line $line_number in $conf_file ignored!\n";
        next;
    }

    #    print "\t", '$parm', " is |$parm|\n";
    my @parms = split( /#/, $parm, 2 );		#split any trailing comment
    clean_string $parms[0];

#    print "\t", '$keyword', " is |$keyword|, ", '$parms[0]', " is |$parms[0]|";
#    if ( $parms[1] ) { print ",  ", '$parms[1]', " is |$parms[1]|"; }
#    print "\n";

    if ( $keyword eq "budget_year" ) {
        $budget_year = $parms[0];
        next;
    }

    if ( $keyword eq "GNUCash_file" ) {
        $GNUCash_file = $parms[0];
        next;
    }

    if ( $keyword eq "report_file" ) {
        $report_file = $parms[0];
        next;
    }

#    if ( $keyword eq "ignore_account" ) {
#        $ignore_account[$ig] = $parms[0];
#        $ig++;
#        next;
#    }

########################################################################
#    If the report account description is empty use the GNUCash account name.
#    The hash key is the GNUCash account name.
#    The arrays contain:
#       the report account description,
#       the monthly budgeted amount,
#       the monthly actual amount,
#       the YTD budgeted amount,
#       the YTD actual amount.
########################################################################
    if ( $keyword eq "map_account" ) {
#print "\t\$_ = |$_|\n";
        ( $GNUCash_account, my $budget_report_account_description ) = split /\>/,$parms[0], 3;
        if ( defined $GNUCash_account ) {
            clean_string $GNUCash_account;
            if ( defined $budget_report_account_description ) {
                clean_string $budget_report_account_description;
            }
            else {
                $budget_report_account_description = $GNUCash_account;
            }

#print "\t\$GNUCash_account is |$GNUCash_account|\n";
#print "\t\$budget_report_account_description is |$budget_report_account_description|\n";

            my @GNUCash_account_split = split /:/,$GNUCash_account, 2;
            if ( "Expenses" eq $GNUCash_account_split[0] || "Income" eq $GNUCash_account_split[0] ) {
                $budget_summary{$GNUCash_account} = [ $budget_report_account_description, 0, 0, 0, 0 ];
            } else {
                print "\t|$GNUCash_account| is neither Expenses or Income!\n";
                print "\t\tLine $line_number in $conf_file ignored!\n\n";
            }
        }
        next;
    }

    print "\t|$keyword| is not a valid keyword\n";
    print "\t\tLine $line_number in $conf_file ignored!\n\n";
}

close INPUT;

#print OUTPUT Dumper( %budget_summary );

#foreach $GNUCash_account ( sort keys %budget_summary )
#   {
#   print OUTPUT "$GNUCash_account:\t",
#                "|$budget_summary{$GNUCash_account}[0]|\t",
#                "|$budget_summary{$GNUCash_account}[1]|\t",
#                "|$budget_summary{$GNUCash_account}[2]|\t",
#                "|$budget_summary{$GNUCash_account}[3]|\t",
#                "|$budget_summary{$GNUCash_account}[4]|",
#                "\n";
#   }

#my $account_count = scalar keys %budget_summary;
#print "Number of Budget Summary Accounts: $account_count\n";


########################################################################
# 1:2 Get month abbreviation or number from command line:
########################################################################
if ( $#ARGV != 0 ) {
    usage;
}

( my $report_month ) = @ARGV;

#print '$report_month = |', $report_month, "|\n";

$report_month =~ tr/a-z/A-Z/;    #Translate to uppercase.

#print '$report_month = |', $report_month, "|\n";

FOR01: for ( my $m = 0 ; $m < 12 ; $m++ ) {
    if ( $report_month eq $month_abbreviations[$m] ) {
        $report_month = $m + 1;
        last FOR01;
    }
}

#print '$report_month = |', $report_month, "|\n";


#At this point $report_month should be numeric. Test for an integer between 1 & 12
if ( $report_month =~ m/^[0-9]+$/ ) { 
    if ( ( $report_month < 1 ) || ( $report_month > 12 ) ) { usage; }
} else { usage; } #$report_month is not an integer

print "\t", '$report_month = |', $report_month, "|\n" if $debug_option;

$first_day_report_month =
  "$budget_year-" . substr( "0" . $report_month, -2 ) . "-01";
my $next_year  = $budget_year;
my $next_month = $report_month + 1;
if ( 12 <= $report_month ) {
    $next_year++;
    $next_month = 1;
}

$first_day_next_month = "$next_year-" . substr( "0" . $next_month, -2 ) . "-01";

#print '$first_day_report_month =|', $first_day_report_month, '|, $first_day_next_month = |', $first_day_next_month, '| $next_year = |', $next_year, '| $next_month = |', $next_month, "|\n";

########################################################################
my $GNUCash_XML_file    = $GNUCash_file;
my $GNUCash_report_file =
  $report_file . "." . $budget_year . substr( "0" . $report_month, -2 ) . ".txt" ;

print "\tThe GNUCash file is\t\t|",        $GNUCash_XML_file,    "|\n";
print "\tThe GNUCash report file is\t|", $GNUCash_report_file, "|\n\n";

########################################################################
# 2: Validate and open the report file
#    Or statements "||" short-circuit, so that if an early part
#    evaluates as true, Perl doesn't bother to evaluate the rest.
#    Here, if the file opens successfully, we don't abort.
########################################################################

my $answer_string = "";
my $output_mode   = "";
if ( -e $GNUCash_report_file ) {            #Exists?
    print STDERR "    Output file $GNUCash_report_file exists!\n";
    until (  $answer_string eq 'r'
          || $answer_string eq 'a'
          || $answer_string eq 'e' )
    {
        print STDERR "    replace(r), append(a), or exit(e)? ";
        chomp( $answer_string = <STDIN> );
    }
    if ( $answer_string eq 'e' ) { exit }
}
if   ( $answer_string eq 'a' ) { $output_mode = '>>' }
else                           { $output_mode = '>' }
open( OUTPUT, "$output_mode$GNUCash_report_file" )
  || die "    Can't output $GNUCash_report_file $!";

########################################################################
# 4: Read and process the transactions in the GNUCash file.
########################################################################

# Unzip the GNUCash file to $XML_string
my $input_file = $GNUCash_XML_file;
my $XML_string;
gunzip $input_file => \$XML_string
    or die "gunzip failed: $GunzipError\n";
#print "\t\$XML_string =|\n",$XML_string, "|\n";
#print Dumper( $XML_string );

# Parse the Gnucash XML in $XML_string
my $xs1 = XML::Simple->new();
my $XML_data = $xs1->XMLin( $XML_string );

print STDERR "Have parsed it\n" if $debug_option;

#print Dumper( $XML_data );

foreach my $GNUCash_XML_key ( keys %$XML_data ) {
    print "GNUCash_XML_key: '$GNUCash_XML_key'\n" if $debug_option;
}

print "#############################################################\n" if $debug_option;

foreach my $GNUCash_XML_gnc_book_key ( keys %{ $XML_data->{'gnc:book'} } ) {
    print "GNUCash_XML_gnc_book_key: '$GNUCash_XML_gnc_book_key'\n" if $debug_option;
}

# GNUCash_XML_key: 'gnc:transaction'
# GNUCash_XML_key: 'gnc:template-transactions'
# GNUCash_XML_key: 'book:id'
# GNUCash_XML_key: 'version'
# GNUCash_XML_key: 'gnc:account'
# GNUCash_XML_key: 'gnc:count-data'
# GNUCash_XML_key: 'gnc:schedxaction'
# GNUCash_XML_key: 'gnc:commodity'

# gnc_book_key: 'book:id'
# gnc_book_key: 'version'
# gnc_book_key: 'gnc:account'
# gnc_book_key: 'gnc:count-data'
# gnc_book_key: 'gnc:budget'
# gnc_book_key: 'gnc:commodity'

########################################################################
# 4.1: Print the 'gnc:count-data'
########################################################################
if ($debug_option) {
    print "\tThere are\n";
    foreach my $count_item ( @{ $XML_data->{'gnc:book'}{'gnc:count-data'} } ) {
        print "\t\t$count_item->{content} $count_item->{'cd:type'} items\n";
    }
}

########################################################################
# 4.2: Read all the accounts.
#      The key is a 32 character hexadecimal identifier.
#      Each entry is a hash ref with the name of the account,
#      the key of its parent, and the type of the account.
########################################################################
my %GNUCash_account_table = map {
    $_->{'act:id'}{content} => {
        name   => $_->{'act:name'},
        parent => $_->{'act:parent'}{content},
        type   => $_->{'act:type'},
      }
} @{ $XML_data->{'gnc:book'}{'gnc:account'} };

#print Dumper( %GNUCash_account_table );

########################################################################
# 4.3: Determine the full name of each account, by prepending its
#      name with that of its parents; each level is separated with a colon.
#
#      Also build an array of arrays of keys at each level.
#      If the tree of accounts has four levels, then @account_levels has
#      four arrays at index 1, 2, 3 and 4.  Each contains the keys
#      at the corresponding level.  It allows traversing the tree
#      one level at a time, starting from the lowest level.
########################################################################
my @account_levels;
my @all_account_names;
my $max_level = 0;
foreach my $GNUCash_account_table_key ( keys %GNUCash_account_table ) {

#$GNUCash_account_table{$GNUCash_account_table_key}{pname} = $GNUCash_account_table{$GNUCash_account_table{$GNUCash_account_table_key}{parent}}{name};

    $GNUCash_account_table{$GNUCash_account_table_key}{fullname} =
      $GNUCash_account_table{$GNUCash_account_table_key}{name};
#print "\$GNUCash_account_table{$GNUCash_account_table_key}{fullname} =|$GNUCash_account_table{$GNUCash_account_table_key}{fullname}|\n";
    my $parent_key = $GNUCash_account_table{$GNUCash_account_table_key}{parent}
      or next;
    my $local_level = 1;
    while ( defined $GNUCash_account_table{$parent_key}{name}
        and $GNUCash_account_table{$parent_key}{name} ne 'Root Account' )
    {
        $GNUCash_account_table{$GNUCash_account_table_key}{fullname} =
"$GNUCash_account_table{$parent_key}{name}:$GNUCash_account_table{$GNUCash_account_table_key}{fullname}";
        $parent_key = $GNUCash_account_table{$parent_key}{parent};
        ++$local_level;
    }
    $GNUCash_account_table{$GNUCash_account_table_key}{level} = $local_level;
    push @{ $account_levels[$local_level] }, $GNUCash_account_table_key;
    $max_level = $local_level if $local_level > $max_level;

#print "\$GNUCash_account_table{$GNUCash_account_table_key}{fullname} =|$GNUCash_account_table{$GNUCash_account_table_key}{fullname}|\n";
#print "$GNUCash_account_table{$GNUCash_account_table_key}{fullname}\n" if $local_level == 4;

# Build an array of account names.
    push ( @all_account_names, $GNUCash_account_table{$GNUCash_account_table_key}{fullname} );

}

print "MAX LEVEL = $max_level\n" if $debug_option;

#print Dumper( %GNUCash_account_table );
#print Dumper( @account_levels );
my $account_count = scalar keys %GNUCash_account_table;
print "NUM Accounts: $account_count\n" if $debug_option;

#@all_account_names = sort @all_account_names;
#print "\@all_account_names :\n @all_account_names\n\n";

########################################################################
# Print all the highest level account names for the Expenses and Income 
#     accounts. These are the ones that might have values entered 
#     in the GNUCash application. The list can/should be used in the
#     configuration file map_account entries.
########################################################################
if ( $list_accounts_option ) {
    my @conf_account_names;
    my $prev_account_name = "";
    print "\nThe accounts suitable for inclusion in configuration file:\n";
    foreach (reverse ( sort @all_account_names ) ) {
    #    print "$_\n";
        if ( -1 == index ( $prev_account_name, $_ ) ) {
            push ( @conf_account_names, $_ );
        }
        $prev_account_name = $_;
    }
    foreach ( sort @conf_account_names ) {
        my @GNUCash_account_split = split /:/,$_, 2;
        if ( "Expenses" eq $GNUCash_account_split[0] || "Income" eq $GNUCash_account_split[0] ) {
            print "$_\n";
        }
    }
    print "End of list of accounts suitable for inclusion in configuration file\n";
}

########################################################################
# 4.4: Add up all the transactions for each account that is
#      within the time period we specify with the start and end options.
########################################################################
my ( $full_name, @dropped_transaction_account, $GNUCash_account_id,
    $split_amount, $transaction_date );

my $transaction_count         = 0;
my $dropped_transaction_index = 0;

TRANSACTION:
foreach my $transaction_item ( @{ $XML_data->{'gnc:book'}{'gnc:transaction'} } )
{
    next unless $transaction_item->{'trn:date-posted'}{'ts:date'};

    ($transaction_date) =
      $transaction_item->{'trn:date-posted'}{'ts:date'} =~ m{^(\d{4}-\d\d-\d\d)}
      or warn "BAD DATE '$transaction_item->{'trn:date-posted'}{'ts:date'}'"
      and next TRANSACTION;

    next if $first_day_next_month le $transaction_date;

    my $split_ref = $transaction_item->{'trn:splits'}{'trn:split'};

    if ( ref $split_ref eq 'ARRAY' ) {

      SPLIT:

        foreach my $split ( ( @{$split_ref} ) ) {

            #            print OUTPUT "\t", '$split', " = |$split|\n";
            $split_amount = value_in_split $split;
            if ( !$split_amount ) { next SPLIT; }

            $GNUCash_account_id = $split->{'split:account'}{content};
            $full_name = $GNUCash_account_table{$GNUCash_account_id}{fullname};

#            print OUTPUT '$GNUCash_account_id = |', $GNUCash_account_id, '|, $split_amount = |', $split_amount, "|,\tFull name = |$GNUCash_account_table{$GNUCash_account_id}{fullname}|\n";
#            print OUTPUT '$full_name = |', $full_name, "|,\t", '$split_amount = |', $split_amount, "|\n";
#            print OUTPUT "Exists\n" if exists $budget_summary{$full_name};
            if ( exists $budget_summary{$full_name} ) {
                $budget_summary{$full_name}[4] += $split_amount;
                if ( $first_day_report_month le $transaction_date ) {
                    $budget_summary{$full_name}[2] += $split_amount;
                }
            }
            else {
                $dropped_transaction_account[$dropped_transaction_index] =
                  $full_name;
                $dropped_transaction_index++;
            }
        }

#    } elsif ( ref $split_ref eq 'HASH' ) {
#	    $split_amount = value_in_split $split_ref;
#            if ( ! $split_amount) { next TRANSACTION; }
#            print OUTPUT '$split_ref->{\'split:account\'} = |', $split_ref->{'split:account'}, '|, $split_amount = |', $split_amount, "|\n";
#            $GNUCash_account = $split_ref->{$split->{'split:account'}{content}}{fullname};
#            print OUTPUT '2-$split_amount = |', $split_amount, "|\n";
#            print OUTPUT '$GNUCash_account = |', $GNUCash_account, '|, $split_amount = |', $split_amount, "|\n";
    }
    else {
        warn "ERROR: REFTYPE OF SPLIT IS '@{[ref $split_ref]}': ",
          Dumper $split_ref;
        next TRANSACTION;
    }

    #    if $first_day_report_month gt $transaction_date;
    ++$transaction_count;
}
print "Number of Transactions: $transaction_count\n" if $debug_option;

#print Dumper( %GNUCash_account_table );
#      $act_ref->{$split->{'split:account'}{content}}{total} += $value;
#      $act_ref->{$split->{'split:account'}{content}}{fullname};

if ($dropped_transaction_index) {
    my $dropped_item_prev = "";
    my $heading_switch = 1;
    foreach my $dropped_item ( sort @dropped_transaction_account ) {
        if ( $dropped_item ne $dropped_item_prev  ) {
            my @GNUCash_account_split = split /:/,$dropped_item, 2;
            if ( "Expenses" eq $GNUCash_account_split[0] || "Income" eq $GNUCash_account_split[0] ) {
                if ( $heading_switch ) {
                    print "\n\tThe following transaction accounts dropped because the account is not in $conf_file\n";
                    $heading_switch = 0;
                }
                print "\t\t$dropped_item\n";
            }
            $dropped_item_prev = $dropped_item;
        }
    }
}

########################################################################
# 5: Add the budgeted amounts to the report.
########################################################################
my (
    $budget_index,           $budget_item, @budget_name,
    @budget_periods,         @budget_ref,  $budget_slot1,
    @dropped_budget_account, $k,           $slot_amount,
    $slot_period
);

my $dropped_budget_index = 0;
my $i = 0;
my $m = 0;

if ( ref $XML_data->{'gnc:book'}{'gnc:budget'} eq 'ARRAY' )
{    #means more than one budget defined
    foreach my $budget_item ( @{ $XML_data->{'gnc:book'}{'gnc:budget'} } ) {
        $budget_name[$i]    = $budget_item->{'bgt:name'};
        $budget_periods[$i] = $budget_item->{'bgt:num-periods'};
        $budget_ref[$i]     = $budget_item;

#        print "\t", '$budget_periods[', $i, "] $budget_periods[$i],\t", '$budget_name[', $i, "] $budget_name[$i]\n";
        $i++;
    }
    $budget_index = $i;

    #    print "\t", '$budget_index', " = |$budget_index|\n";

    if ( $i > 1 ) {
        print "\tThere are $budget_index budgets defined.\n";
        for ( $k = 1 ; $k <= $i ; $k++ ) {
            print "\t\t[$k]: $budget_name[$k - 1]\n";
        }
        until ( ( $m > 0 ) && ( $m <= $k ) ) {
            print
"\tEnter the number for the desired budget name ( or $k to exit ): ";
            chomp( $m = <STDIN> );
            if ( $m == $k ) { exit; }
        }
        $budget_index = $m;

        #        print "\t", '$budget_index', " = |$budget_index|\n";
    }

    $budget_index--;

#    print "\t", '$budget_index', " = |$budget_index|\n";
#    print OUTPUT Dumper( $budget_ref[$budget_index] );
#    print "\t", '$budget_ref[$budget_index]->{\'bgt:name\'} = |', "$budget_ref[$budget_index]->{'bgt:name'}|\n";

    my ( $slot_amount, $slot_period );
    foreach $budget_slot1 (
        @{ $budget_ref[$budget_index]->{'bgt:slots'}{'slot'} } )
    {

        #        print OUTPUT "\t", '$budget_slot1', " = |$budget_slot1|\n";
        budget_detail($budget_slot1);
    }
}

if ( ref $XML_data->{'gnc:book'}{'gnc:budget'} eq 'HASH' )
{    #means only one budget defined

    #    print OUTPUT Dumper( $XML_data->{'gnc:book'}{'gnc:budget'} );
    foreach $budget_slot1 (
        @{ $XML_data->{'gnc:book'}{'gnc:budget'}{'bgt:slots'}{'slot'} } )
    {

        #        print OUTPUT "\t", '$budget_slot1', " = |$budget_slot1|\n";
        budget_detail($budget_slot1);

#        print OUTPUT Dumper( $budget_slot1 );
#        print OUTPUT "\t", '$budget_slot1->{\'slot:key\'}', " = |$budget_slot1->{'slot:key'}|\n";
    }
}

##########################################################################################################################
sub budget_detail {    # process detail budget items

    #        print OUTPUT "\t", '@_', " = |@_|\n";
    my ($budget_slot2) = @_;
    $GNUCash_account_id = $budget_slot2->{'slot:key'};
    $full_name          = $GNUCash_account_table{$GNUCash_account_id}{fullname};

    #        print OUTPUT "\t\t", '$full_name = |', $full_name, "|\n";

    #       If {'slot:value'}{'slot'} is a hash the following works.
    if ( ref $budget_slot2->{'slot:value'}{'slot'} eq 'HASH' ) {
        $slot_period = $budget_slot2->{'slot:value'}{'slot'}{'slot:key'};
        $slot_amount = eval(
            $budget_slot2->{'slot:value'}{'slot'}{'slot:value'}{'content'} );

#            print OUTPUT "\t\t", '$slot_period = |', $slot_period, "|\n";
#            print OUTPUT "\t\t", '$slot_amount = |', $slot_amount, "|\n";
#            if ( exists $budget_summary{$full_name} ) {
#                if ( ( $slot_period  + 1 ) == $report_month ) { $budget_summary{$full_name}[1] += $slot_amount; }
#                if ( ( $slot_period  + 1 ) <= $report_month ) { $budget_summary{$full_name}[3] += $slot_amount; }
#            }
        budget_detail_2();
    }

    #       If {'slot:value'}{'slot'} is an array the following works.
    if ( ref $budget_slot2->{'slot:value'}{'slot'} eq 'ARRAY' ) {
        foreach my $budget_slot3 ( @{ $budget_slot2->{'slot:value'}{'slot'} } )
        {
            $slot_period = $budget_slot3->{'slot:key'};
            $slot_amount = eval( $budget_slot3->{'slot:value'}{'content'} );

#                print OUTPUT "\t\t", '$slot_period = |', $slot_period, "|\n";
#                print OUTPUT "\t\t", '$slot_amount = |', $slot_amount, "|\n";
#                if ( exists $budget_summary{$full_name} ) {
#                    if ( ( $slot_period  + 1 ) == $report_month ) { $budget_summary{$full_name}[1] += $slot_amount; }
#                    if ( ( $slot_period  + 1 ) <= $report_month ) { $budget_summary{$full_name}[3] += $slot_amount; }
#                }
            budget_detail_2();
        }
    }
}
##########################################################################################################################

##########################################################################################################################
sub budget_detail_2 {    # add budget amount to budget summary table
    if ( exists $budget_summary{$full_name} ) {
        if ( ( $slot_period + 1 ) == $report_month ) {
            $budget_summary{$full_name}[1] += $slot_amount;
        }
        if ( ( $slot_period + 1 ) <= $report_month ) {
            $budget_summary{$full_name}[3] += $slot_amount;
        }
    }
    else {
        if ( ( $slot_period + 1 ) <= $report_month ) {
            $dropped_budget_account[$dropped_budget_index] = $full_name;
            $dropped_budget_index++;
        }
    }
}
##########################################################################################################################

if ($dropped_budget_index) {
    my $dropped_item_prev = "";
    print
"\n\tThe following budgeted accounts dropped because the account is not in $conf_file\n";
    foreach my $dropped_item ( sort @dropped_budget_account ) {
        if ( $dropped_item ne $dropped_item_prev ) {
            print "\t\t$dropped_item\n";
            $dropped_item_prev = $dropped_item;
        }
    }
}

########################################################################
# 6: Output the budget report.
########################################################################
#foreach $GNUCash_account ( sort keys %budget_summary )
#   {
#   print OUTPUT "$GNUCash_account:\t",
#                "|$budget_summary{$GNUCash_account}[0]|\t",
#                "|$budget_summary{$GNUCash_account}[1]|\t",
#                "|$budget_summary{$GNUCash_account}[2]|\t",
#                "|$budget_summary{$GNUCash_account}[3]|\t",
#                "|$budget_summary{$GNUCash_account}[4]|",
#                "\n";
#   }
my $actual_multiplier =
  1;    #sign must be reversed for actual amounts of Income Items
my $A1             = "";
my $first_switch01 = 1;
my (
    $S1, $S2, $S3, $S4, $S5, $S6, $T1, $T2, $T3,
    $T4, $T5, $T6, $V1, $V2, $V3, $V4, $V5, $V6
);
$S1 = $S2 = $S3 = $S4 = $S5 = $S6 = $T1 = $T2 = $T3 = $T4 = $T5 = $T6 = $V1 =
  $V2 = $V3 = $V4 = $V5 = $V6 = 0;

print OUTPUT
  "Monthly Budget Summary, $month_names[$report_month-1] $budget_year\n\n";

print OUTPUT
"                               BUDGETED      ACTUAL                     YTD         YTD     AVERAGE\n";
print OUTPUT
"DESCRIPTION                     AMOUNTS     AMOUNTS    VARIANCE    VARIANCE      ACTUAL      ACTUAL\n";

#FOR02:
foreach $GNUCash_account ( sort keys %budget_summary ) {
    $A1 = $budget_summary{$GNUCash_account}[0];
    if ( $A1 eq "Do_Not_Print" ) {

        if ( ( 0 == $budget_summary{$GNUCash_account}[1] ) &
            ( 0 == $budget_summary{$GNUCash_account}[2] ) &
            ( 0 == $budget_summary{$GNUCash_account}[3] ) &
            ( 0 == $budget_summary{$GNUCash_account}[4] ) )
        {
            next;
        }

#        foreach my $ignore_item ( @ignore_account ) {
##            print "\t", '$ignore_item', " = |$ignore_item|, ", '$GNUCash_account', " = |$GNUCash_account|\n";
#            if ( $GNUCash_account eq $ignore_item ) { next FOR02; }
#        }

        if ($first_switch01) {
            print "\n\tThe following GNUCash accounts have budgeted and/or actual amounts but there is no\n" ,
                "\t\treport description specified in the following transaction accounts:\n";
            $first_switch01 = 0;
        }
        print "\t$GNUCash_account\n";
        print "\t\t$month_abbreviations[$report_month-1] Budgeted Amount = $budget_summary{$GNUCash_account}[1]\n";
        print "\t\t$month_abbreviations[$report_month-1] Actual   Amount = $budget_summary{$GNUCash_account}[2]\n";
        print "\t\tYTD Budgeted Amount = $budget_summary{$GNUCash_account}[3]\n";
        print "\t\tYTD Actual   Amount = $budget_summary{$GNUCash_account}[4]\n";
        next;
    }

    #    print OUTPUT '$A1 = |', $A1, "|\n";
    if ( $A1 eq "Expenses" ) {
        print OUTPUT "\nEXPENSES\n";
        next;
    }
    if ( $A1 eq "Income" ) {
        $A1 = "SUBTOTAL";
        $V1 = $S1;
        $V2 = $S2;
        $V3 = $S3;
        $V4 = $S4;
        $V5 = $S5;
        $V6 = $S5 / $report_month;
        write OUTPUT;
        $T1 = $S1;
        $T2 = $S2;
        $T3 = $S3;
        $T4 = $S4;
        $T5 = $S5;
        $S1 = $S2 = $S3 = $S4 = $S5 = 0;
        print OUTPUT "\nINCOME\n";
        $actual_multiplier = -1;
        next;
    }
    $V1 = $budget_summary{$GNUCash_account}[1];
    $V2 = $budget_summary{$GNUCash_account}[2] * $actual_multiplier;
    $V3 = $V1 - $V2;
    $V5 = $budget_summary{$GNUCash_account}[4] * $actual_multiplier;
    $V4 = $budget_summary{$GNUCash_account}[3] - $V5;
    $V6 = $V5 / $report_month;

    write OUTPUT;

    $S1 += $V1;
    $S2 += $V2;
    $S3 += $V3;
    $S4 += $V4;
    $S5 += $V5;
}
$A1 = "SUBTOTAL";
$V1 = $S1;
$V2 = $S2;
$V3 = $S3;
$V4 = $S4;
$V5 = $S5;
$V6 = $S5 / $report_month;
write OUTPUT;
print OUTPUT "\n";
$A1 = "TOTAL";
$V1 = $S1 - $T1;
$V2 = $S2 - $T2;
$V3 = $S3 - $T3;
$V4 = $S4 - $T4;
$V5 = $S5 - $T5;
$V6 = $V5 / $report_month;
my $prev_csf = select(OUTPUT);
$~ = "TOTALS";    #Change the format for OUTPUT
write OUTPUT;

########################################################################
# 7: Done!
########################################################################

close INPUT;
close OUTPUT;

exec 'gedit', $GNUCash_report_file;

exit;

#*************************************************************************************************************************************
format OUTPUT =
@<<<<<<<<<<<<<<<<<<<<<<<<<<@########.##@########.##@########.##@########.##@########.##@########.##
$A1, $V1, $V2, $V3, $V4, $V5, $V6
.

#*************************************************************************************************************************************

#*************************************************************************************************************************************
format TOTALS =
@<<<<<<<<<<<<<<<<<<<<<<<<<<@########.##@########.##                        @########.##@########.##
$A1, $V1, $V2, $V5, $V6
.

#*************************************************************************************************************************************

#foreach my $key ( keys %{$transaction_item->{'trn:splits'}} ) {
#    print OUTPUT "KEY: '$key'\n";
#}
#print OUTPUT Dumper( %{$transaction_item->{'trn:splits'}} );
#exit;
#    next unless $transaction_item->{'trn:splits'};
#    next unless $transaction_item->{'trn:splits'}{'trn:split'};
#    next unless $transaction_item->{'trn:splits'}{'trn:split'}{'split:id'};
#    my ( $GNUCash_account1 ) = $transaction_item->{'trn:splits'}{'trn:split'}{'split:id'};

##########################################################################################################################
sub clean_number {    # Clean up numeric fields.
    $_[0] =~
      s/\s*\$*\,*//g;    # remove 0 or more spaces, dollar signs, and commas.
    if ( "" eq $_[0] ) {
        $_[0] = 0;       # make null fields zero.
    }
}

