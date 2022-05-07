# --
# Copyright (C) 2017 - 2022 Perl-Services.de, https://www.perl-services.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Modules::AdminTableCheck;

use strict;
use warnings;

use Kernel::Language qw(Translatable);

our @ObjectDependencies = qw(
    Kernel::System::PerlServices::TableCheck
);

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    $Self->{DBType} = $Self->_GetDBType();

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');

    my @Tables = $ParamObject->GetArray( Param => 'Table' );

    if ( $Self->{Subaction} eq 'SetCollation' ) {
        my $Output = $Self->_SetCollation(
            Tables => \@Tables,
        );

        return $Output;
    }

    my $Output = $LayoutObject->Header();
    $Output .= $LayoutObject->NavigationBar();
    $Output .= $Self->_CheckTableCollations();
    $Output .= $LayoutObject->Footer();

    return $Output;
}


sub _SetCollation {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $DBObject     = $Kernel::OM->Get('Kernel::System::DB');

    my $Collation     = $ParamObject->GetParam( Param => 'Collation' );

    my $Notifications = '';

    TABLE:
    for my $Table ( @{ $Param{Tables} || [] } ) {
        my $EscapedTable = $DBObject->{dbh}->quote_identifier( $Table );

        my $SQL = qq~ALTER TABLE $EscapedTable CONVERT TO CHARACTER SET utf8 COLLATE $Collation~;

        next TABLE if !$Collation;
        next TABLE if $DBObject->Do( SQL => $SQL );

        $Notifications .= $LayoutObject->Notify(
            Priority => 'Error',
            Info     => $LayoutObject->{LanguageObject}->Translate(
                "Table %s could not be converted to %s",
                $Table,
                $Collation,
            ),
        );
    }

    my $Output = $LayoutObject->Header();
    $Output .= $LayoutObject->NavigationBar();
    $Output .= $Notifications;
    $Output .= $Self->_CheckTableCollations();
    $Output .= $LayoutObject->Footer();

    return $Output;
}

sub _CheckTableCollations {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $DBObject     = $Kernel::OM->Get('Kernel::System::DB');

    my ($SQL, $Columns) = $Self->_GetDBInfo( Check => 'Collations' );

    $DBObject->Prepare( SQL => $SQL );

    my $TableIndex = $Columns->{table};
    my $CollIndex  = $Columns->{collation};

    my %Tables;
    my %CollationsUsed;

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my $Table     = $Row[$TableIndex];
        my $Collation = $Row[$CollIndex];

        $Tables{$Table} = $Collation;
        $CollationsUsed{$Collation}++;
    }

    $Param{CollationsSelect} = $LayoutObject->BuildSelection(
        Name         => 'Collation',
        Data         => [ sort keys %CollationsUsed ],
        Class        => 'Modernize',
        PossibleNone => 1,
    );

    $LayoutObject->Block(
        Name => 'CollationCheck',
        Data => \%Param,
    );

    for my $Table ( sort keys %Tables ) {
        $LayoutObject->Block(
            Name => 'Table',
            Data => {
                Table     => $Table,
                Collation => $Tables{$Table},
            },
        );
    }

    return $LayoutObject->Output(
        TemplateFile => 'AdminTableCheck',
        Data         => \%Param
    );
}

sub _GetDBInfo {
    my ( $Self, %Param ) = @_;

    my $Type  = $Self->{DBType};
    my $Check = $Param{Check};

    my %Mapping = (
        Collations => {
            mysql => {
                sql     => 'show table status',
                columns => {
                    table     => 0,
                    collation => 14,
                },
            },
        },
    );

    my %Info = %{ $Mapping{$Check}->{$Type} || {} };
    return ( $Info{sql}, $Info{columns} );
}

sub _GetDBType {
    my ( $Self, %Param ) = @_;

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $DSN          = $ConfigObject->Get('DatabaseDSN');

    my (undef, $Type) = split /:/, $DSN;
    $Self->{DBType}   = lc $Type;
}

1;
