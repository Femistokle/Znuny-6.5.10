# --
# Copyright (C) 2021 Znuny GmbH, https://znuny.org/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --
package Kernel::System::DynamicField::Driver::WebserviceDropdown;

use strict;
use warnings;

use Data::UUID;

use Kernel::System::VariableCheck qw(:all);
use Kernel::System::DB;

use parent qw(Kernel::System::DynamicField::Driver::Dropdown);
use parent qw(Kernel::System::DynamicField::Driver::BaseWebservice);

our @ObjectDependencies = (
    'Kernel::Output::HTML::Layout',
    'Kernel::System::DynamicField::Webservice',
    'Kernel::System::DynamicFieldValue',
    'Kernel::System::JSON',
);

sub ValueSet {
    my ( $Self, %Param ) = @_;

    my $DynamicFieldValueObject = $Kernel::OM->Get('Kernel::System::DynamicFieldValue');

    # if there is at least one value to set, this means one or more values are selected,
    #    set those values!
    if ( IsStringWithData( $Param{Value} ) ) {
        my $Success = $DynamicFieldValueObject->ValueSet(
            FieldID  => $Param{DynamicFieldConfig}->{ID},
            ObjectID => $Param{ObjectID},
            Value    => [
                {
                    ValueText => $Param{Value},
                },
            ],
            UserID => $Param{UserID},
        );

        return $Success;
    }

    # otherwise no value was selected, then in fact this means that any value there should be
    # deleted
    my $Success = $DynamicFieldValueObject->ValueDelete(
        FieldID  => $Param{DynamicFieldConfig}->{ID},
        ObjectID => $Param{ObjectID},
        UserID   => $Param{UserID},
    );

    return $Success;
}

sub EditFieldRender {
    my ( $Self, %Param ) = @_;

    my $JSONObject = $Kernel::OM->Get('Kernel::System::JSON');

    # take config from field config
    my $FieldConfig = $Param{DynamicFieldConfig}->{Config};
    my $FieldName   = 'DynamicField_' . $Param{DynamicFieldConfig}->{Name};
    my $FieldLabel  = $Param{DynamicFieldConfig}->{Label};

    my $Value             = '';
    my $DefaultSearchTerm = '';

    # set the field value or default
    if ( $Param{UseDefaultValue} ) {
        $Value = ( defined $FieldConfig->{DefaultValue} ? $FieldConfig->{DefaultValue} : '' );
    }
    $Value = $Param{Value} // $Value;

    if ( $FieldConfig->{DefaultSearchTerm} ) {
        $DefaultSearchTerm = $Param{LayoutObject}->Ascii2Html(
            Text => $FieldConfig->{DefaultSearchTerm},
        );
    }

    # extract the dynamic field value from the web request
    my $FieldValue = $Self->EditFieldValueGet(
        %Param,
    );

    # set values from ParamObject if present
    if ( IsStringWithData($FieldValue) ) {
        $Value = $FieldValue;
    }

    # check and set class if necessary
    my $FieldClass = 'DynamicFieldText Modernize';
    if ( defined $Param{Class} && $Param{Class} ne '' ) {
        $FieldClass .= ' ' . $Param{Class};
    }

    $FieldClass .= ' W' . ( $FieldConfig->{InputFieldWidth} // 50 ) . 'pc';

    # set field as mandatory
    if ( $Param{Mandatory} ) {
        $FieldClass .= ' Validate_Required';
    }

    # set error css class
    if ( $Param{ServerError} ) {
        $FieldClass .= ' ServerError';
    }

    # set TreeView class
    if ( $FieldConfig->{TreeView} ) {
        $FieldClass .= ' DynamicFieldWithTreeView';
    }

    # set PossibleValues, use PossibleValuesFilter if defined
    my $PossibleValues = $Param{PossibleValuesFilter} // $Self->PossibleValuesGet(%Param);

    my $DataValues = $Self->BuildSelectionDataGet(
        DynamicFieldConfig => $Param{DynamicFieldConfig},
        PossibleValues     => $PossibleValues,
        Value              => $Value,
    );

    # add default value if no DataValues exists
    if ( !IsHashRefWithData($DataValues) && IsStringWithData($Value) ) {
        $DataValues = { $Value => $Value };
    }

    my $HTMLString = $Param{LayoutObject}->BuildSelection(
        Data         => $DataValues || {},
        Name         => $FieldName,
        SelectedID   => $Value,
        Translation  => $FieldConfig->{TranslatableValues} || 0,
        PossibleNone => 1,
        TreeView     => $FieldConfig->{TreeView} || 0,
        Class        => $FieldClass,
        HTMLQuote    => 1,
        Multiple     => 0,
    );

    if ( $FieldConfig->{TreeView} ) {
        my $TreeSelectionMessage = $Param{LayoutObject}->{LanguageObject}->Translate("Show Tree Selection");
        $HTMLString
            .= ' <a href="#" title="'
            . $TreeSelectionMessage
            . '" class="ShowTreeSelection"><span>'
            . $TreeSelectionMessage . '</span><i class="fa fa-sitemap"></i></a>';
    }

    # Tooltip for client side validation
    my $ClientErrorTooltipDivID = $FieldName . 'Error';
    my $FieldRequiredMessage    = $Param{LayoutObject}->{LanguageObject}->Translate("This field is required.");
    $HTMLString .= <<"EOF";
<div id="$ClientErrorTooltipDivID" class="TooltipErrorMessage">
    <p>
        $FieldRequiredMessage
    </p>
</div>
EOF

    # Tooltip for server side validation
    my $ErrorMessage = $Param{ErrorMessage} || 'This field is required.';
    $ErrorMessage = $Param{LayoutObject}->{LanguageObject}->Translate($ErrorMessage);
    my $ServerErrorTooltipDivID = $FieldName . 'ServerError';
    $HTMLString .= <<"EOF";
<div id="$ServerErrorTooltipDivID" class="TooltipErrorMessage">
    <p>
        $ErrorMessage
    </p>
</div>
EOF

    my $AutocompleteMinLength = int( $FieldConfig->{AutocompleteMinLength} || 3 );
    my $QueryDelay            = int( $FieldConfig->{QueryDelay}            || 500 );
    my $TicketID              = $Param{LayoutObject}->{TicketID};

    if ( !IsArrayRefWithData( $FieldConfig->{AdditionalDFStorage} ) ) {
        $FieldConfig->{AdditionalDFStorage} = [];
    }

    my @AdditionalDFStorage = grep { $_->{Type} ne 'Backend' } @{ $FieldConfig->{AdditionalDFStorage} };
    my @AdditionalDFs       = map  { $_->{DynamicField} } @AdditionalDFStorage;

    my $AdditionalDFs = $JSONObject->Encode(
        Data => \@AdditionalDFs,
    );

    # Add attributes needed for Znuny.DynamicField.Webservice.InitDynamicField() to created HTML string.
    # BuildSelection() does not support HTML attributes.
    my $DynamicFieldName      = $Param{DynamicFieldConfig}->{Name};
    my $DynamicFieldFieldType = $Param{DynamicFieldConfig}->{FieldType};
    my $DynamicFieldSearch    = $FieldName . '_Search';

    my $UUIDObject     = Data::UUID->new();
    my $InputFieldUUID = lc $UUIDObject->create_str();

    $HTMLString
        =~ s{(<select )}{$1 data-dynamic-field-name="$DynamicFieldName" data-dynamic-field-type="$DynamicFieldFieldType" data-selected-value-field-name="$FieldName" data-autocomplete-field-name="$DynamicFieldSearch" data-autocomplete-min-length="$AutocompleteMinLength" data-query-delay="$QueryDelay" data-default-search-term="$DefaultSearchTerm" data-ticket-id="$TicketID" data-input-field-uuid="$InputFieldUUID" };

    # Add InitSelect for search.
    my $DynamicFieldJS = <<"EOF";
    // Initialize JS for dynamic field.
    Znuny.DynamicField.Webservice.InitSelect('$InputFieldUUID', '$Param{DynamicFieldConfig}->{Name}', '$FieldName', '${FieldName}_Search', $AutocompleteMinLength, $QueryDelay, '$DefaultSearchTerm', '$TicketID', $AdditionalDFs);
EOF
    $Param{LayoutObject}->AddJSOnDocumentComplete( Code => $DynamicFieldJS );

    my $LabelString = $Self->EditLabelRender(
        %Param,
        Mandatory => $Param{Mandatory} || '0',
        FieldName => $FieldName,
    );

    my $Data = {
        Field => $HTMLString,
        Label => $LabelString,
    };

    return $Data;
}

sub EditFieldValueValidate {
    my ( $Self, %Param ) = @_;

    # get the field value from the http request
    my $Value = $Self->EditFieldValueGet(
        DynamicFieldConfig => $Param{DynamicFieldConfig},
        ParamObject        => $Param{ParamObject},

        # not necessary for this Driver but place it for consistency reasons
        ReturnValueStructure => 1,
    );

    my $ServerError;
    my $ErrorMessage;

    # perform necessary validations
    if ( $Param{Mandatory} && !IsStringWithData($Value) ) {
        return {
            ServerError => 1,
        };
    }

    # create resulting structure
    my $Result = {
        ServerError  => $ServerError,
        ErrorMessage => $ErrorMessage,
    };

    return $Result;
}

sub DisplayValueRender {
    my ( $Self, %Param ) = @_;

    # Fetch display value from dynamic field Webservice.
    my $DynamicFieldWebserviceObject = $Kernel::OM->Get('Kernel::System::DynamicField::Webservice');

    return $Self->SUPER::DisplayValueRender(%Param) if !defined $Param{Value};

    my $TicketID = $Param{LayoutObject}->{TicketID};
    $Param{Value} = $DynamicFieldWebserviceObject->DisplayValueGet(
        DynamicFieldConfig => $Param{DynamicFieldConfig},
        Value              => $Param{Value},
        TicketID           => $TicketID,
    );

    return $Self->SUPER::DisplayValueRender(%Param);
}

# this function is used in AgentTicketCompose via TemplateGenerator
sub ReadableValueRender {
    my ( $Self, %Param ) = @_;

    my $DynamicFieldWebserviceObject = $Kernel::OM->Get('Kernel::System::DynamicField::Webservice');

    # set Value and Title variables
    my $Value = '';
    my $Title = '';

    if ( IsStringWithData( $Param{Value} ) ) {
        $Value = $DynamicFieldWebserviceObject->Template(
            %Param,
            DynamicFieldConfig => $Param{DynamicFieldConfig},
            Value              => $Param{Value},
            Type               => 'Value',
        );
    }

    $Title = $Value;

    # cut strings if needed
    if ( $Param{ValueMaxChars} && length($Value) > $Param{ValueMaxChars} ) {
        $Value = substr( $Value, 0, $Param{ValueMaxChars} ) . '...';
    }

    if ( $Param{TitleMaxChars} && length($Title) > $Param{TitleMaxChars} ) {
        $Title = substr( $Title, 0, $Param{TitleMaxChars} ) . '...';
    }

    # create return structure
    my $Data = {
        Value => $Value,
        Title => $Title,
    };

    return $Data;
}

sub SearchFieldRender {
    my ( $Self, %Param ) = @_;

    my $DynamicFieldWebserviceObject = $Kernel::OM->Get('Kernel::System::DynamicField::Webservice');
    my $JSONObject                   = $Kernel::OM->Get('Kernel::System::JSON');

    # take config from field config
    my $FieldConfig = $Param{DynamicFieldConfig}->{Config};
    my $FieldName   = 'Search_DynamicField_' . $Param{DynamicFieldConfig}->{Name};
    my $FieldLabel  = $Param{DynamicFieldConfig}->{Label};

    # get the field value, this function is always called after the profile is loaded
    my $FieldValues = $Self->SearchFieldValueGet(
        %Param,
    ) // [];

    # check and set class if necessary
    my $FieldClass = 'DynamicFieldMultiSelect Modernize';

    my $SelectionData = {};
    if ( IsArrayRefWithData($FieldValues) ) {
        my $TicketID = $Param{LayoutObject}->{TicketID};
        $SelectionData = $DynamicFieldWebserviceObject->DisplayValueGet(
            DynamicFieldConfig => $Param{DynamicFieldConfig},
            Value              => $FieldValues,
            Limit              => '',
            TicketID           => $TicketID,
        ) // {};
    }

    # Make sure to have at least a selectable "empty" value so the dropdown is not displayed
    # as read-only.
    $SelectionData->{'-'} //= ' ';

    my $HTMLString = $Param{LayoutObject}->BuildSelection(
        Data         => $SelectionData,
        Name         => $FieldName,
        SelectedID   => $FieldValues,
        Translation  => $FieldConfig->{TranslatableValues} || 0,
        PossibleNone => 1,
        TreeView     => 0,
        Class        => $FieldClass,
        Multiple     => 1,
        HTMLQuote    => 1,
    );

    my $DefaultSearchTerm = '';
    if ( $FieldConfig->{DefaultSearchTerm} ) {
        $DefaultSearchTerm = $Param{LayoutObject}->Ascii2Html(
            Text => $FieldConfig->{DefaultSearchTerm},
        );
    }

    my $AutocompleteMinLength = int( $FieldConfig->{AutocompleteMinLength} || 3 );
    my $QueryDelay            = int( $FieldConfig->{QueryDelay}            || 1 );
    my $TicketID              = $Param{LayoutObject}->{TicketID};

    if ( !IsArrayRefWithData( $FieldConfig->{AdditionalDFStorage} ) ) {
        $FieldConfig->{AdditionalDFStorage} = [];
    }

    my @AdditionalDFStorage = grep { $_->{Type} ne 'Backend' } @{ $FieldConfig->{AdditionalDFStorage} };
    my @AdditionalDFs       = map  { $_->{DynamicField} } @AdditionalDFStorage;

    my $AdditionalDFs = $JSONObject->Encode(
        Data => \@AdditionalDFs,
    );

    # Add attributes needed for Znuny.DynamicField.Webservice.InitDynamicField() to created HTML string.
    # BuildSelection() does not support HTML attributes.
    my $DynamicFieldName      = $Param{DynamicFieldConfig}->{Name};
    my $DynamicFieldFieldType = $Param{DynamicFieldConfig}->{FieldType};
    my $DynamicFieldSearch    = $FieldName . '_Search';

    my $UUIDObject     = Data::UUID->new();
    my $InputFieldUUID = lc $UUIDObject->create_str();

    $HTMLString
        =~ s{(<select )}{$1 data-dynamic-field-name="$DynamicFieldName" data-dynamic-field-type="$DynamicFieldFieldType" data-selected-value-field-name="$FieldName" data-autocomplete-field-name="$DynamicFieldSearch" data-autocomplete-min-length="$AutocompleteMinLength" data-query-delay="$QueryDelay" data-default-search-term="$DefaultSearchTerm" data-ticket-id="$TicketID" data-input-field-uuid="$InputFieldUUID" };

    # Add InitSelect for search.
    my $DynamicFieldJS = <<"EOF";
    // Initialize JS for dynamic field.
    Znuny.DynamicField.Webservice.InitSelect('$InputFieldUUID', '$Param{DynamicFieldConfig}->{Name}', '$FieldName', '${FieldName}_Search', $AutocompleteMinLength, $QueryDelay, '$DefaultSearchTerm', '$TicketID', $AdditionalDFs);
EOF
    $Param{LayoutObject}->AddJSOnDocumentComplete( Code => $DynamicFieldJS );

    my $LabelString = $Self->EditLabelRender(
        %Param,
        FieldName => $FieldName,
    );

    my $Data = {
        Field => $HTMLString,
        Label => $LabelString,
    };

    return $Data;
}

sub SearchFieldValueGet {
    my ( $Self, %Param ) = @_;

    $Self->_CustomSearchFormTransformTextToStoredValue(%Param);

    return Kernel::System::DynamicField::Driver::BaseSelect::SearchFieldValueGet( $Self, %Param );
}

sub SearchFieldParameterBuild {
    my ( $Self, %Param ) = @_;

    return Kernel::System::DynamicField::Driver::BaseSelect::SearchFieldParameterBuild( $Self, %Param );
}

sub ValueLookup {
    my ( $Self, %Param ) = @_;

    my $DynamicFieldWebserviceObject = $Kernel::OM->Get('Kernel::System::DynamicField::Webservice');

    return $Param{Key} if !IsStringWithData( $Param{Key} );

    my $TicketID = $Param{LayoutObject}->{TicketID};
    my $Value    = $DynamicFieldWebserviceObject->DisplayValueGet(
        DynamicFieldConfig => $Param{DynamicFieldConfig},
        Value              => $Param{Key},
        TicketID           => $TicketID,
    );

    return $Value;
}

sub BuildSelectionDataGet {
    my ( $Self, %Param ) = @_;

    my $FieldConfig            = $Param{DynamicFieldConfig}->{Config};
    my $FilteredPossibleValues = $Param{PossibleValues};

    # get the possible values again as it might or might not contain the possible none and it could
    # also be overwritten
    my $ConfigPossibleValues = $Self->PossibleValuesGet(%Param);

    if ( $Param{Value} && $ConfigPossibleValues ) {
        $FilteredPossibleValues = $ConfigPossibleValues;
    }

    # check if $PossibleValues differs from configured PossibleValues
    # and show values which are not contained as disabled if TreeView => 1
    return $FilteredPossibleValues if !$FieldConfig->{TreeView};
    return $FilteredPossibleValues if keys %{$ConfigPossibleValues} == keys %{$FilteredPossibleValues};

    # define variables to use later in the for loop
    my @Values;
    my $Parents;
    my %DisabledElements;
    my %ProcessedElements;
    my $PossibleNoneSet;

    my %Values;
    if ( defined $Param{Value} && IsArrayRefWithData( $Param{Value} ) ) {

        # create a lookup table
        %Values = map { $_ => 1 } @{ $Param{Value} };
    }

    # loop on all filtered possible values
    KEY:
    for my $Key ( sort keys %{$FilteredPossibleValues} ) {

        # special case for possible none
        if ( !$Key && !$PossibleNoneSet && $FieldConfig->{PossibleNone} ) {
            my $Selected;
            if (
                !%Values
                || ( defined $Values{''} && $Values{''} )
                )
            {
                $Selected = 1;
            }

            # add possible none
            push @Values, {
                Key      => $Key,
                Value    => $ConfigPossibleValues->{$Key} || '-',
                Selected => $Selected,
            };

            $PossibleNoneSet = 1;
            next KEY;
        }

        # try to split its parents GrandParent::Parent::Son
        my @Elements = split /::/, $Key;

        # reset parents
        $Parents = '';

        # get each element in the hierarchy
        ELEMENT:
        for my $Element (@Elements) {

            # add its own parents for the complete name
            my $ElementLongName = $Parents . $Element;

            # set new parent (before skip already processed)
            $Parents .= $Element . '::';

            # skip if already processed
            next ELEMENT if $ProcessedElements{$ElementLongName};

            my $Disabled;

            # check if element exists in the original data or if it is already marked
            if (
                !defined $FilteredPossibleValues->{$ElementLongName}
                && !$DisabledElements{$ElementLongName}
                )
            {

                # mark element as disabled
                $DisabledElements{$ElementLongName} = 1;

                # also set the disabled flag for current element to add
                $Disabled = 1;
            }

            # set element as already processed
            $ProcessedElements{$ElementLongName} = 1;

            # check if the current element is the selected one
            my $Selected;
            if ( %Values && $Values{$ElementLongName} ) {
                $Selected = 1;
            }

            # add element to the new list of possible values (now including missing parents)
            push @Values, {
                Key      => $ElementLongName,
                Value    => $ConfigPossibleValues->{$ElementLongName} || $ElementLongName,
                Disabled => $Disabled,
                Selected => $Selected,
            };
        }
    }

    $FilteredPossibleValues = \@Values;

    return $FilteredPossibleValues;
}

sub PossibleValuesGet {
    my ( $Self, %Param ) = @_;

    my $DynamicFieldWebserviceObject = $Kernel::OM->Get('Kernel::System::DynamicField::Webservice');
    my $LayoutObject                 = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    my %PossibleValues;

    # Provide empty value so the field will not be displayed as disabled if there are no selectable
    # values yet.
    $PossibleValues{' '} = '';

    my $TicketID = $Param{LayoutObject}->{TicketID};
    if ( $Param{DynamicFieldConfig}->{Config}->{InitialSearchTerm} ) {
        my $InitialSearchTerm = $LayoutObject->Ascii2Html(
            Text => $Param{DynamicFieldConfig}->{Config}->{InitialSearchTerm},
        );

        my $Results = $DynamicFieldWebserviceObject->Autocomplete(
            DynamicFieldConfig => $Param{DynamicFieldConfig},
            SearchTerms        => $InitialSearchTerm,
            UserID             => $Param{UserID},
            TicketID           => $TicketID,
        );
        if ( IsArrayRefWithData($Results) ) {
            for my $Result ( @{$Results} ) {
                $PossibleValues{ $Result->{StoredValue} } = $Result->{DisplayValue};
            }
        }
    }

    # set all other possible values if defined on field config
    if ( IsHashRefWithData( $Param{DynamicFieldConfig}->{Config}->{PossibleValues} ) ) {
        %PossibleValues = (
            %PossibleValues,
            %{ $Param{DynamicFieldConfig}->{Config}->{PossibleValues} },
        );
    }

    if ( IsStringWithData( $Param{Value} ) ) {
        my $DisplayValue = $DynamicFieldWebserviceObject->DisplayValueGet(
            DynamicFieldConfig => $Param{DynamicFieldConfig},
            Value              => [ $Param{Value} ],
            TicketID           => $TicketID,
        );

        %PossibleValues = (
            %PossibleValues,
            %{$DisplayValue},
        );
    }

    return \%PossibleValues;
}

# This is in here because the original Kernel::System::DynamicFieldValue::HistoricalValuesGet() uses a cache
sub StatsFieldParameterBuild {
    my ( $Self, %Param ) = @_;

    # set PossibleValues
    my $Values = $Param{DynamicFieldConfig}->{Config}->{PossibleValues} // {};

    # get historical values from webservice
    my $HistoricalValues = $Self->_HistoricalValueGet(
        FieldID => $Param{DynamicFieldConfig}->{ID},
    );

    # add historic values to current values (if they don't exist anymore)
    KEY:
    for my $Key ( sort keys %{$HistoricalValues} ) {
        next KEY if $Values->{$Key};
        $Values->{$Key} = $HistoricalValues->{$Key};
    }

    # use PossibleValuesFilter if defined
    $Values = $Param{PossibleValuesFilter} // $Values;

    return {
        Values             => $Values,
        Name               => $Param{DynamicFieldConfig}->{Label},
        Element            => 'DynamicField_' . $Param{DynamicFieldConfig}->{Name},
        TranslatableValues => $Param{DynamicFieldconfig}->{Config}->{TranslatableValues},
        Block              => 'MultiSelectField',
    };
}

sub StatsSearchFieldParameterBuild {
    my ( $Self, %Param ) = @_;

    return Kernel::System::DynamicField::Driver::BaseSelect::StatsSearchFieldParameterBuild( $Self, %Param );
}

sub FieldValueValidate {
    my ( $Self, %Param ) = @_;

    return 1;
}

sub HistoricalValuesGet {
    my ( $Self, %Param ) = @_;

    return;
}

1;
