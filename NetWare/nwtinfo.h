
/*
 * Copyright � 2001 Novell, Inc. All Rights Reserved.
 *
 * You may distribute under the terms of either the GNU General Public
 * License or the Artistic License, as specified in the README file.
 *
 */

/*
 * FILENAME		:	NWTInfo.h
 * DESCRIPTION	:	Thread-local storage for Perl.
 * Author		:	SGP, HYAK
 * Date			:	January 2001.
 *
 */



#ifndef __NWTInfo_H__
#define __NWTInfo_H__


#include "win32ish.h"		// For "BOOL", "TRUE" and "FALSE"

typedef struct tagThreadInfo
{
	int tid;
	struct tagThreadInfo *next;
	BOOL	m_dontTouchHashLists;
	void*	m_allocList;
}ThreadInfo;


void fnInitializeThreadInfo(void);
BOOL fnTerminateThreadInfo(void);
BOOL fnRegisterWithThreadTable(void);
BOOL fnUnregisterWithThreadTable(void);

ThreadInfo* fnAddThreadInfo(int tid);
BOOL fnRemoveThreadInfo(int tid);
ThreadInfo* fnGetThreadInfo(int tid);

//For storing and retrieving Watcom Hash list address
BOOL fnInsertHashListAddrs(void *addrs, BOOL dontTouchHashList);
BOOL fnGetHashListAddrs(void **addrs, BOOL *dontTouchHashList);

//New TLS to set and get the thread contex - may be redundant,
//or see if the above portion can be removed once this works properly
typedef struct tagThreadCtx
{
	long tid;
	void *tInfo;
	struct tagThreadCtx *next;
}ThreadContext;


long fnInitializeThreadCtx(void);
ThreadContext* fnAddThreadCtx(long lTLSIndex, void *t);
BOOL fnRemoveThreadCtx(long lTLSIndex);
void* fnGetThreadCtx(long lTLSIndex);

#endif	// __NWTInfo_H__

