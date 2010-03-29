// Copyright (c) 2010 Trevor Squires. All Rights Reserved.
// See License.txt for full license.

#import "JPAckWindowController.h"
#import "JPAckResultSource.h"
#import "JPAckResultRep.h"
#import "JPAckResultCell.h"

@interface JPAckResultSource ()
@property(nonatomic, copy) NSString* longestLineNumber;
@property(nonatomic, retain) NSMutableArray* resultLines;
@property(nonatomic, copy, readwrite) NSString* resultStats;
- (void)configureFontAttributes;
- (CGFloat)lineContentWidth;
- (void)adjustForLongestLineNumber:(NSString*)linenumber;
@end

@implementation JPAckResultSource

NSString* const amLineNumberColumn = @"amLineNumberColumn";
NSString* const amContentColumn  = @"amContentColumn";

@synthesize longestLineNumber;
@synthesize searchRoot;
@synthesize resultStats;
@synthesize resultLines;
@synthesize matchedFiles;
@synthesize matchedLines;

- (void)awakeFromNib
{
  currentResultFile = nil;
  resultStats = nil;
  searchRoot = nil;
  longestLineNumber = nil;

  self.resultLines = [NSMutableArray array];

  [resultView setIntercellSpacing:NSMakeSize(0,0)];

  NSArray* rvColumns = [resultView tableColumns];
  NSAssert([rvColumns count] == 2, @"Expected 2 columns in output table");
  [[rvColumns objectAtIndex:0] setIdentifier:amLineNumberColumn];
  [[rvColumns objectAtIndex:1] setIdentifier:amContentColumn];

  [self configureFontAttributes];
}

- (void)clearContents
{
  alternateRow = NO;
  matchedFiles = 0;
  matchedLines = 0;
  currentResultFile = nil;
  self.resultStats = nil;
  [self.resultLines removeAllObjects];
  [resultView reloadData];

  // reset column 0 to be 3 chars wide in the current font
  self.longestLineNumber = nil;
  [self adjustForLongestLineNumber:@"..."];
}

- (void)updateStats
{
  // 5 lines matched in 2 files
  NSString* insel = (searchingSelection) ? @"In selection: " : @"";
  
  self.resultStats = [NSString stringWithFormat:@"%@%d line%@ matched in %d file%@", insel, matchedLines, (matchedLines == 1) ? @"" : @"s", matchedFiles, (matchedFiles == 1) ? @"" : @"s"];
}

- (void)searchingFor:(NSString*)term inRoot:(NSString*)searchRoot_ inFolder:(NSString*)searchFolder
{
  self.searchRoot = searchRoot_;
  searchingSelection = (searchFolder) ? YES : NO;
  [self updateStats];
}

- (void)parsedError:(NSString*)errorString
{
  alternateRow = NO;
  JPAckResult* jpar = [JPAckResult resultErrorWithString:errorString];
  [self.resultLines addObject:[JPAckResultRep withResultObject:jpar alternate:alternateRow]];
  [resultView noteNumberOfRowsChanged];
}

- (void)parsedFilename:(NSString*)filename
{
  alternateRow = NO;
  matchedFiles++;
  [self updateStats];

  currentResultFile = [JPAckResult resultFileWithName:[filename substringFromIndex:[self.searchRoot length]]];
  [self.resultLines addObject:[JPAckResultRep withResultObject:currentResultFile alternate:NO]];
  [resultView noteNumberOfRowsChanged];
}

- (void)parsedContextBreak
{
  alternateRow = NO;
  JPAckResult* jpar = [JPAckResult resultContextBreak];
  [self.resultLines addObject:[JPAckResultRep withResultObject:jpar alternate:NO]];
  [resultView noteNumberOfRowsChanged];
}

- (void)parsedContextLine:(NSString*)lineNumber content:(NSString*)content
{
  if (currentResultFile)
  {
    JPAckResult* jpar = [JPAckResult resultContextLineWithNumber:lineNumber content:content];
    [self.resultLines addObject:[JPAckResultRep withResultObject:jpar parent:currentResultFile alternate:alternateRow]];
    alternateRow = !alternateRow;
    [resultView noteNumberOfRowsChanged];
    [self adjustForLongestLineNumber:lineNumber];
  }
}

- (void)parsedMatchLine:(NSString*)lineNumber ranges:(NSArray*)ranges content:(NSString*)content
{
  if (currentResultFile)
  {
    NSMutableArray* matchRanges = (ranges) ? [NSMutableArray arrayWithCapacity:[ranges count]] : nil;
    matchedLines++;

    for (NSString* rangeString in ranges)
      [matchRanges addObject:[NSValue valueWithRange:NSRangeFromString(rangeString)]];

    JPAckResult* jpar = [JPAckResult resultMatchingLineWithNumber:lineNumber content:content ranges:matchRanges];
    [self.resultLines addObject:[JPAckResultRep withResultObject:jpar parent:currentResultFile alternate:alternateRow]];
    alternateRow = !alternateRow;
    [resultView noteNumberOfRowsChanged];
    [self adjustForLongestLineNumber:lineNumber];
  }
}

- (void)adjustForLongestLineNumber:(NSString*)lineNumber
{
  if ([lineNumber length] > [self.longestLineNumber length])
  {
    self.longestLineNumber = lineNumber;
    CGFloat lineNumberWidth = ceil(RESULT_ROW_PADDING + (RESULT_CONTENT_INTERIOR_PADDING * 2.0) + (RESULT_TEXT_XINSET * 2.0) + [lineNumber sizeWithAttributes:bodyNowrapAttributes].width);

    [[resultView tableColumnWithIdentifier:amLineNumberColumn] setWidth:lineNumberWidth];
    [resultView sizeLastColumnToFit];
    
    NSIndexSet* refreshIndexes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [resultView numberOfRows])];
    [resultView noteHeightOfRowsWithIndexesChanged:refreshIndexes];
  }
}

- (CGFloat)lineContentWidth
{
  return NSWidth([resultView rectOfColumn:1]) - RESULT_ROW_PADDING - (RESULT_TEXT_XINSET * 2.0) - (RESULT_CONTENT_INTERIOR_PADDING * 2);
}

- (NSInteger)tableView:(NSTableView *)tableView spanningColumnForRow:(NSInteger)row
{
  JPAckResultType rt = [[self.resultLines objectAtIndex:row] resultType];
  if (rt == JPResultTypeFilename || rt == JPResultTypeError)
    return 1;

  return NSNotFound;
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row
{
  JPAckResultRep* resultRep = [self.resultLines objectAtIndex:row];

  switch([resultRep resultType])
  {
    case JPResultTypeFilename:
      return headerHeight;
    case JPResultTypeContextBreak:
      return contextBreakHeight;
  }

  CGFloat maxWidth = [self lineContentWidth];

  if (resultRep.constrainedWidth != maxWidth)
  {
    NSSize constraints = NSMakeSize(maxWidth, MAXFLOAT);
    resultRep.constrainedWidth = maxWidth;
    resultRep.calculatedHeight = (RESULT_TEXT_YINSET * 2) + NSHeight([[resultRep.resultObject lineContent] boundingRectWithSize:constraints options:(NSStringDrawingUsesLineFragmentOrigin) attributes:bodyAttributes]);
  }
  return resultRep.calculatedHeight;
}

- (BOOL)tableView:(NSTableView *)tableView shouldShowCellExpansionForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
  return NO;
}

- (BOOL)tableView:(NSTableView *)tableView activateSelectedRow:(NSInteger)row
{
  JPAckResultRep* rep = [self.resultLines objectAtIndex:row];
  JPAckResult* resultObject = [rep resultObject];

  if (resultObject.resultType == JPResultTypeContext || resultObject.resultType == JPResultTypeMatchingLine)
  {
    NSString* filenameToOpen = [[rep parentObject] lineContent];
    [windowController openProjectFile:filenameToOpen atLine:[resultObject lineNumber]];
    return YES;
  }

  return NO;
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row
{
  JPAckResultType itemtype = [[self.resultLines objectAtIndex:row] resultType];
  return (itemtype == JPResultTypeMatchingLine || itemtype == JPResultTypeContext);
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
  return [self.resultLines count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
  JPAckResultRep* rep = [self.resultLines objectAtIndex:row];
  JPAckResultType resultType = [rep resultType];
  id value = nil;
  
  if ([tableColumn identifier] == amLineNumberColumn)
  {
    value = (resultType == JPResultTypeContextBreak) ? @"..." : [[rep resultObject] lineNumber];
  }
  else if ([tableColumn identifier] == amContentColumn)
  {
    NSString* lineContent = [[rep resultObject] lineContent];
    if (!lineContent)
      lineContent = @"";

    if ([rep resultType] == JPResultTypeMatchingLine)
    {
      NSRange contentRange = NSMakeRange(0, [lineContent length]);

      NSMutableAttributedString* attributedContent = [[[NSMutableAttributedString alloc] initWithString:lineContent attributes:bodyAttributes] autorelease];
      for (NSValue* rv in [[rep resultObject] matchRanges])
        [attributedContent setAttributes:bodyHighlightAttributes range:NSIntersectionRange([rv rangeValue], contentRange)];

      value = attributedContent;
    }
    else if ([rep resultType] == JPResultTypeFilename)
      value = [[[NSMutableAttributedString alloc] initWithString:lineContent attributes:headingAttributes] autorelease];
    else
      value = lineContent;
  }
  
  return value;
}

- (BOOL)tableView:(NSTableView *)tableView isStickyRow:(NSInteger)row
{
  return ([[self.resultLines objectAtIndex:row] resultType] == JPResultTypeFilename);
}

- (void)tableView:(NSTableView *)tableView willDisplayCell:(id)aCell forTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)row
{
  JPAckResultRep* rep = [self.resultLines objectAtIndex:row];
  [(JPAckResultCell*)aCell configureType:[rep resultType] alternate:[rep alternate] contentColumn:([aTableColumn identifier] != amLineNumberColumn)];
}

- (BOOL)tableView:(NSTableView *)tableView shouldTrackCell:(NSCell *)cell forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
  return NO;
}

- (void)configureFontAttributes
{
  NSFontManager* fm = [NSFontManager sharedFontManager];

  NSFont* headingFont = [NSFont fontWithName:@"Trebuchet MS Bold" size:13.0];
  if (!headingFont)
    headingFont = [NSFont boldSystemFontOfSize:13.0];

  NSFont* bodyFont = [NSFont fontWithName:@"Menlo-Regular" size:11.0];
  if (!bodyFont)
    bodyFont = [NSFont fontWithName:@"Monaco" size:11.0];
  
  if (!bodyFont)
    bodyFont = [NSFont userFixedPitchFontOfSize:11.0];

  NSFont* boldBodyFont = [fm convertWeight:YES ofFont:bodyFont];

  // Heading (filename) attributes
  NSMutableParagraphStyle* nowrapStyle = [[[NSMutableParagraphStyle alloc] init] autorelease];
  [nowrapStyle setLineBreakMode:NSLineBreakByTruncatingTail];

  headingAttributes = [[NSDictionary alloc] initWithObjectsAndKeys:
    headingFont, NSFontAttributeName,
    nowrapStyle, NSParagraphStyleAttributeName,
    nil];

  // Body (output context/matches) sans-wrapping
  bodyNowrapAttributes = [[NSDictionary alloc] initWithObjectsAndKeys:
    bodyFont, NSFontAttributeName,
    [[nowrapStyle copy] autorelease], NSParagraphStyleAttributeName,
    nil];

  // Body (output context/matches) attributes
  NSMutableParagraphStyle* wrapStyle = [[[NSMutableParagraphStyle alloc] init] autorelease];
  [wrapStyle setLineBreakMode:NSLineBreakByWordWrapping];

  // Force tabstops to be 2 characters wide
  CGFloat tabWidth = [@".." sizeWithAttributes:bodyNowrapAttributes].width;
  [wrapStyle setTabStops:[NSArray array]];
  [wrapStyle setDefaultTabInterval:tabWidth];

  bodyAttributes = [[NSDictionary alloc] initWithObjectsAndKeys:
    bodyFont, NSFontAttributeName,
    wrapStyle, NSParagraphStyleAttributeName,
    nil];

  // Body highlight (matched character ranges) attributes
  bodyHighlightAttributes = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
    boldBodyFont, NSFontAttributeName,
    [NSColor colorWithCalibratedRed:(255.0/255.0) green:(225.0/255.0) blue:(68.0/255.0) alpha:1.0], NSBackgroundColorAttributeName,
    nil];

  // Make sure the table is using our chosen font
  for (NSTableColumn* tc in [resultView tableColumns])
    [[tc dataCell] setFont:bodyFont];

  // Precalculate a few row heights:
  headerHeight = RESULT_ROW_PADDING + (RESULT_TEXT_YINSET * 2) + [@"Jiminy!" sizeWithAttributes:headingAttributes].height;
  contextBreakHeight = (RESULT_TEXT_YINSET * 2) + [@"Jiminy!" sizeWithAttributes:bodyAttributes].height;
}

- (void)dealloc
{
  [searchRoot release], searchRoot = nil;
  [resultStats release], resultStats = nil;
  [resultLines release], resultLines = nil;
  [longestLineNumber release], longestLineNumber = nil;

  [headingAttributes release], headingAttributes = nil;
  [bodyAttributes release], bodyAttributes = nil;
  [bodyNowrapAttributes release], bodyNowrapAttributes = nil;
  [bodyHighlightAttributes release], bodyHighlightAttributes = nil;

  [super dealloc];
}
@end
