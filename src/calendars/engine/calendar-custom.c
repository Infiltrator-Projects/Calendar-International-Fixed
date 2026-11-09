// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 1993-2026 Shannon Smith

/* International Fixed chronology over Gregorian years.
 * Its 13 named months and exceptional Leap/Year Days use one descriptor. */

#include "calendar-custom.h"
#include "calendar-ancient.h"
#include "calendar-bahai.h"
#include "calendar-helpers.h"
#include "calendar-historical.h"
#include "calendar-perpetual.h"
#include "calendar-reform.h"
#include "julian-day.h"

#include <glib/gi18n-lib.h>

/* Only this chronology is compiled into the standalone calendar resource. */

typedef CalendarCalendarMode CalendarMode;
typedef CalendarCalendarFields CalendarFields;

typedef void (*FieldsFromJdnFunc)(gint64 jdn, CalendarFields *fields);
typedef gint64 (*FieldsToJdnFunc)(const CalendarFields *fields);
typedef gint (*MonthLengthFunc)(const CalendarFields *fields);
typedef gchar *(*FormatFunc)(const CalendarFields *fields,
                             CalendarDatePart part);
typedef gint (*PeriodIndexFunc)(gint month);
typedef gint (*MonthFromPeriodFunc)(gint period);

typedef struct
{
    FieldsFromJdnFunc fields_from_jdn;
    FieldsToJdnFunc fields_to_jdn;
    MonthLengthFunc month_length;
    FormatFunc format;
    PeriodIndexFunc period_index;
    MonthFromPeriodFunc month_from_period;
    gint periods_per_year;
    gint period_origin_day;
} CustomCalendarProvider;

#define floor_divide calendar_floor_divide
#define positive_modulo calendar_positive_modulo

static const gchar *const fixed_months[] = {
    "", N_("January"), N_("February"), N_("March"), N_("April"),
    N_("May"), N_("June"), N_("Sol"), N_("July"), N_("August"),
    N_("September"), N_("October"), N_("November"), N_("December")
};


static gint
fixed_month_length(const CalendarFields *fields)
{
    return calendar_fixed_month_length(fields->year, fields->month);
}

static gint
default_period_index(gint month)
{
    return month - 1;
}

static gint
default_month_from_period(gint period)
{
    return period + 1;
}

static gchar *
format_fixed(const CalendarFields *fields,
             CalendarDatePart part)
{
    if (part == CALENDAR_DATE_PART_DAY && fields->special)
        return g_strdup(fields->month == 6 ? "L" : "Y");
    if (fields->special &&
        part != CALENDAR_DATE_PART_MONTH &&
        part != CALENDAR_DATE_PART_YEAR)
    {
        return g_strdup_printf("%s, %" G_GINT64_FORMAT,
                               fields->month == 6 ?
                               _("Leap Day") : _("Year Day"),
                               fields->year);
    }

    return calendar_format_named_date(fields, part, fixed_months, G_N_ELEMENTS(fixed_months), NULL);
}

/* Only the International Fixed mode is valid for this standalone provider. */
static const CustomCalendarProvider fixed_provider = {
    calendar_fixed_fields_from_jdn,
    calendar_fixed_fields_to_jdn,
    fixed_month_length, format_fixed,
    default_period_index, default_month_from_period,
    13, 1
};

static const CustomCalendarProvider *
custom_provider(CalendarMode mode)
{
    return mode == CALENDAR_CALENDAR_MODE_INTERNATIONAL_FIXED
        ? &fixed_provider : NULL;
}

void
calendar_custom_fields_from_jdn(CalendarMode mode,
                                     gint64 jdn,
                                     CalendarFields *fields)
{
    (void)mode;
    const CustomCalendarProvider *provider = custom_provider(mode);

    g_return_if_fail(fields != NULL);
    *fields = (CalendarFields){0};

    if (provider != NULL)
        provider->fields_from_jdn(jdn, fields);
}

gchar *
calendar_custom_format(CalendarMode mode,
                            const CalendarFields *fields,
                            CalendarDatePart part)
{
    (void)mode;
    const CustomCalendarProvider *provider = custom_provider(mode);

    if (provider == NULL || fields == NULL || provider->format == NULL)
        return g_strdup("");

    return provider->format(fields, part);
}

gint64
calendar_custom_month_start(CalendarMode mode,
                                 gint64 jdn)
{
    (void)mode;
    const CustomCalendarProvider *provider = custom_provider(mode);
    CalendarFields fields;

    if (provider == NULL)
        return CALENDAR_UNIX_EPOCH_JDN;

    provider->fields_from_jdn(jdn, &fields);
    fields.day = provider->period_origin_day;
    return provider->fields_to_jdn(&fields);
}

gint64
calendar_custom_add_months(CalendarMode mode,
                                gint64 jdn,
                                gint amount)
{
    (void)mode;
    const CustomCalendarProvider *provider = custom_provider(mode);
    CalendarFields fields;
    gint64 serial;
    gint period;

    if (provider == NULL)
        return jdn;


    provider->fields_from_jdn(jdn, &fields);
    period = provider->period_index(fields.month);
    serial = calendar_i64_add_saturating(
        calendar_i64_add_saturating(
            calendar_i64_multiply_saturating(
                fields.year, provider->periods_per_year),
            period),
        amount);
    fields.year = floor_divide(serial, provider->periods_per_year);
    period = (gint)positive_modulo(serial, provider->periods_per_year);
    fields.month = provider->month_from_period(period);
    fields.day = MIN(fields.day, provider->month_length(&fields));

    return provider->fields_to_jdn(&fields);
}

gint64
calendar_custom_add_years(CalendarMode mode,
                               gint64 jdn,
                               gint amount)
{
    (void)mode;
    const CustomCalendarProvider *provider = custom_provider(mode);
    CalendarFields fields;

    if (provider == NULL)
        return jdn;


    provider->fields_from_jdn(jdn, &fields);
    fields.year = calendar_i64_add_saturating(fields.year, amount);
    fields.day = MIN(fields.day, provider->month_length(&fields));

    return provider->fields_to_jdn(&fields);
}


