CLASS zcl_abapgit_version DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.

    CLASS-METHODS normalize
      IMPORTING
        !iv_version       TYPE string
      RETURNING
        VALUE(rv_version) TYPE string .
    CLASS-METHODS conv_str_to_version
      IMPORTING
        !iv_version       TYPE csequence
      RETURNING
        VALUE(rs_version) TYPE zif_abapgit_definitions=>ty_version
      RAISING
        zcx_abapgit_exception .
    CLASS-METHODS check_dependant_version
      IMPORTING
        !is_current   TYPE zif_abapgit_definitions=>ty_version
        !is_dependant TYPE zif_abapgit_definitions=>ty_version
      RAISING
        zcx_abapgit_exception .
    CLASS-METHODS compare
      IMPORTING
        !iv_a            TYPE string OPTIONAL
        !iv_b            TYPE string OPTIONAL
        !is_a            TYPE zif_abapgit_definitions=>ty_version OPTIONAL
        !is_b            TYPE zif_abapgit_definitions=>ty_version OPTIONAL
      RETURNING
        VALUE(rv_result) TYPE i .
    CLASS-METHODS get_version_constant_value
      IMPORTING
        iv_version_constant TYPE string
      RETURNING
        VALUE(rv_version)   TYPE string
      RAISING
        zcx_abapgit_exception.
    CLASS-METHODS parse_version_from_source
      IMPORTING
        it_source         TYPE string_table
        iv_component_name TYPE csequence
      RETURNING
        VALUE(rv_version) TYPE string
      RAISING
        zcx_abapgit_exception.
  PROTECTED SECTION.
  PRIVATE SECTION.

    CLASS-METHODS version_to_numeric
      IMPORTING
        !iv_version       TYPE string
      RETURNING
        VALUE(rv_version) TYPE i.
ENDCLASS.



CLASS zcl_abapgit_version IMPLEMENTATION.


  METHOD check_dependant_version.

    CONSTANTS: lc_message TYPE string VALUE 'Current version is older than required'.

    IF is_dependant-major > is_current-major.
      zcx_abapgit_exception=>raise( lc_message ).
    ELSEIF is_dependant-major < is_current-major.
      RETURN.
    ENDIF.

    IF is_dependant-minor > is_current-minor.
      zcx_abapgit_exception=>raise( lc_message ).
    ELSEIF is_dependant-minor < is_current-minor.
      RETURN.
    ENDIF.

    IF is_dependant-patch > is_current-patch.
      zcx_abapgit_exception=>raise( lc_message ).
    ELSEIF is_dependant-patch < is_current-patch.
      RETURN.
    ENDIF.

    IF is_current-prerelase IS INITIAL.
      RETURN.
    ENDIF.

    CASE is_current-prerelase.
      WHEN 'rc'.
        IF is_dependant-prerelase = ''.
          zcx_abapgit_exception=>raise( lc_message ).
        ENDIF.

      WHEN 'beta'.
        IF is_dependant-prerelase = '' OR is_dependant-prerelase = 'rc'.
          zcx_abapgit_exception=>raise( lc_message ).
        ENDIF.

      WHEN 'alpha'.
        IF is_dependant-prerelase = '' OR is_dependant-prerelase = 'rc' OR is_dependant-prerelase = 'beta'.
          zcx_abapgit_exception=>raise( lc_message ).
        ENDIF.

    ENDCASE.

    IF is_dependant-prerelase = is_current-prerelase AND is_dependant-prerelase_patch > is_current-prerelase_patch.
      zcx_abapgit_exception=>raise( lc_message ).
    ENDIF.

  ENDMETHOD.


  METHOD compare.

    DATA: ls_version_a TYPE zif_abapgit_definitions=>ty_version,
          ls_version_b TYPE zif_abapgit_definitions=>ty_version.

    TRY.
        IF is_a IS NOT INITIAL.
          ls_version_a = is_a.
        ELSE.
          ls_version_a = conv_str_to_version( iv_a ).
        ENDIF.

        IF is_b IS NOT INITIAL.
          ls_version_b = is_b.
        ELSE.
          ls_version_b = conv_str_to_version( iv_b ).
        ENDIF.
      CATCH zcx_abapgit_exception.
        rv_result = 0.
        RETURN.
    ENDTRY.

    IF ls_version_a = ls_version_b.
      rv_result = 0.
    ELSE.
      TRY.
          check_dependant_version( is_current   = ls_version_a
                                   is_dependant = ls_version_b ).
          rv_result = 1.
        CATCH zcx_abapgit_exception.
          rv_result = -1.
          RETURN.
      ENDTRY.
    ENDIF.

  ENDMETHOD.


  METHOD conv_str_to_version.

    DATA: lt_segments TYPE STANDARD TABLE OF string,
          lt_parts    TYPE STANDARD TABLE OF string,
          lv_segment  TYPE string.

    SPLIT iv_version AT '-' INTO TABLE lt_segments.

    READ TABLE lt_segments INTO lv_segment INDEX 1. " Version
    IF sy-subrc <> 0.   " No version
      RETURN.
    ENDIF.

    SPLIT lv_segment AT '.' INTO TABLE lt_parts.

    LOOP AT lt_parts INTO lv_segment.

      TRY.
          CASE sy-tabix.
            WHEN 1.
              rs_version-major = lv_segment.
            WHEN 2.
              rs_version-minor = lv_segment.
            WHEN 3.
              rs_version-patch = lv_segment.
          ENDCASE.
        CATCH cx_sy_conversion_no_number.
          zcx_abapgit_exception=>raise( 'Incorrect format for Semantic Version' ).
      ENDTRY.

    ENDLOOP.

    READ TABLE lt_segments INTO lv_segment INDEX 2. " Pre-release Version
    IF sy-subrc <> 0.   " No version
      RETURN.
    ENDIF.

    SPLIT lv_segment AT '.' INTO TABLE lt_parts.

    LOOP AT lt_parts INTO lv_segment.

      CASE sy-tabix.
        WHEN 1.
          rs_version-prerelase = lv_segment.
          TRANSLATE rs_version-prerelase TO LOWER CASE.
        WHEN 2.
          rs_version-prerelase_patch = lv_segment.
      ENDCASE.

    ENDLOOP.

    IF rs_version-prerelase <> 'rc' AND rs_version-prerelase <> 'beta' AND rs_version-prerelase <> 'alpha'.
      zcx_abapgit_exception=>raise( 'Incorrect format for Semantic Version' ).
    ENDIF.

  ENDMETHOD.


  METHOD normalize.

    " Internal program version should be in format "XXX.XXX.XXX" or "vXXX.XXX.XXX"
    CONSTANTS:
      lc_version_pattern    TYPE string VALUE '^v?(\d{1,3}\.\d{1,3}\.\d{1,3})\s*$',
      lc_prerelease_pattern TYPE string VALUE '^((rc|beta|alpha)\.\d{1,3})\s*$'.

    DATA: lv_version      TYPE string,
          lv_prerelease   TYPE string,
          lv_version_n    TYPE string,
          lv_prerelease_n TYPE string.

    SPLIT iv_version AT '-' INTO lv_version lv_prerelease.

    FIND FIRST OCCURRENCE OF REGEX lc_version_pattern
      IN lv_version SUBMATCHES lv_version_n.

    IF lv_prerelease IS NOT INITIAL.

      FIND FIRST OCCURRENCE OF REGEX lc_prerelease_pattern
        IN lv_prerelease SUBMATCHES lv_prerelease_n.

    ENDIF.

    IF lv_version_n IS INITIAL.
      RETURN.
    ENDIF.

    rv_version = lv_version_n.

    IF lv_prerelease_n IS NOT INITIAL.
      CONCATENATE rv_version '-' lv_prerelease_n INTO rv_version.
    ENDIF.

  ENDMETHOD.


  METHOD version_to_numeric.

    DATA: lv_major   TYPE n LENGTH 4,
          lv_minor   TYPE n LENGTH 4,
          lv_release TYPE n LENGTH 4.

    SPLIT iv_version AT '.' INTO lv_major lv_minor lv_release.

    " Calculated value of version number, empty version will become 0 which is OK
    rv_version = lv_major * 1000000 + lv_minor * 1000 + lv_release.

  ENDMETHOD.

  METHOD get_version_constant_value.
    DATA: lv_version_class     TYPE string,
          lv_version_component TYPE string.
    FIELD-SYMBOLS: <lv_version> TYPE string.

    IF iv_version_constant NP '*=>*'.
      zcx_abapgit_exception=>raise( 'Version constant needs to use the format CLASS=>CONSTANT' ).
    ENDIF.

    SPLIT iv_version_constant AT '=>' INTO lv_version_class lv_version_component.
    IF sy-subrc <> 0 OR lv_version_class IS INITIAL OR lv_version_component IS INITIAL.
      zcx_abapgit_exception=>raise( 'Version constant cannot be parsed' ).
    ENDIF.

    ASSIGN (lv_version_class)=>(lv_version_component) TO <lv_version>.
    IF sy-subrc = 0.
      rv_version = <lv_version>.
    ELSE.
      zcx_abapgit_exception=>raise( |Could not access version at class { lv_version_class } component | &&
                                    |{ lv_version_component }| ).
    ENDIF.
  ENDMETHOD.

  METHOD parse_version_from_source.
    TYPES: ty_statement TYPE c LENGTH 40.
    CONSTANTS: BEGIN OF c_token_types,
                 identifier TYPE stokes-type VALUE 'I',
                 literal    TYPE stokes-type VALUE 'S',
               END OF c_token_types.
    DATA: lt_keyword_filter    TYPE STANDARD TABLE OF ty_statement,
          lt_statements        TYPE sstmnt_tab,
          lt_tokens            TYPE stokes_tab,
          lt_structures        TYPE sstruc_tab,
          lv_found_token_index TYPE i,
          lv_component_name    TYPE string,
          lv_version_length    TYPE i.
    FIELD-SYMBOLS: <ls_structure> TYPE sstruc,
                   <ls_statement> TYPE sstmnt,
                   <ls_token>     TYPE stokes.

    IF iv_component_name CA '-'.
      zcx_abapgit_exception=>raise( 'Structured version constants are not supported' ).
    ENDIF.

    lv_component_name = condense( to_upper( iv_component_name ) ).

    APPEND 'CONSTANTS' TO lt_keyword_filter.

    SCAN ABAP-SOURCE it_source
      KEYWORDS FROM lt_keyword_filter
      STATEMENTS INTO lt_statements
      TOKENS INTO lt_tokens
      STRUCTURES INTO lt_structures.
    IF sy-subrc <> 0.
      zcx_abapgit_exception=>raise( 'Source code could not be parsed to extract version (syntax error?)' ).
    ENDIF.

    READ TABLE lt_structures ASSIGNING <ls_structure> WITH KEY type = 'P'.
    IF sy-subrc <> 0.
      zcx_abapgit_exception=>raise( 'Could not find top level structure to parse version constant' ).
    ENDIF.

    LOOP AT lt_statements FROM <ls_structure>-stmnt_from TO <ls_structure>-stmnt_to ASSIGNING <ls_statement>.
      LOOP AT lt_tokens FROM <ls_statement>-from TO <ls_statement>-to
           TRANSPORTING NO FIELDS
           WHERE type = c_token_types-identifier AND str = lv_component_name.
        lv_found_token_index = sy-tabix.
        EXIT.
      ENDLOOP.

      IF sy-subrc = 0.
        LOOP AT lt_tokens FROM lv_found_token_index TO <ls_statement>-to
             TRANSPORTING NO FIELDS
             WHERE type = c_token_types-identifier AND str = 'VALUE'.
          lv_found_token_index = sy-tabix.
          EXIT.
        ENDLOOP.

        IF lv_found_token_index + 1 > <ls_statement>-to.
          zcx_abapgit_exception=>raise( 'Internal error parsing version constant' ).
        ENDIF.

        READ TABLE lt_tokens INDEX lv_found_token_index + 1 ASSIGNING <ls_token>.
        IF sy-subrc <> 0.
          zcx_abapgit_exception=>raise( 'Internal error parsing version constant' ).
        ENDIF.

        CASE <ls_token>-type.
          WHEN c_token_types-identifier.
            rv_version = <ls_token>-str.
            IF rv_version(1) CA sy-abcde.
              zcx_abapgit_exception=>raise(
                'References to other constants are not supported in version constant value' ).
            ENDIF.
          WHEN c_token_types-literal.
            rv_version = <ls_token>-str.
            IF rv_version CP '`*`' OR rv_version CP `'*'`.
              lv_version_length = strlen( rv_version ).
              rv_version = substring(
                             val = rv_version
                             off = 1
                             len = lv_version_length - 2 ).
            ENDIF.
        ENDCASE.

        CONDENSE rv_version.

        RETURN.
      ENDIF.
    ENDLOOP.

    zcx_abapgit_exception=>raise( |Could not parse version constant { iv_component_name }| ).
  ENDMETHOD.
ENDCLASS.
