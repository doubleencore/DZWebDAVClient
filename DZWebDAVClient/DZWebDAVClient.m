//
//  DZWebDAVClient.m
//  DZWebDAVClient
//

#import "DZWebDAVClient.h"
#import "DZDictionaryRequestOperation.h"
#import "NSDate+RFC1123.h"
#import "NSDate+ISO8601.h"
#import "DZWebDAVLock.h"

NSString const *DZWebDAVContentTypeKey		= @"getcontenttype";
NSString const *DZWebDAVContentLengthKey	= @"lp1:getcontentlength";
NSString const *DZWebDAVETagKey				= @"lp1:getetag";
NSString const *DZWebDAVCTagKey				= @"getctag";
NSString const *DZWebDAVCreationDateKey		= @"lp1:creationdate";
NSString const *DZWebDAVModificationDateKey	= @"lp1:getlastmodified";
NSString const *DZWebDAVResourceTypeKey     = @"g0:resourcetype";

@interface DZWebDAVClient()
- (void)mr_listPath:(NSString *)path depth:(NSUInteger)depth success:(void(^)(AFHTTPRequestOperation *, id))success failure:(void(^)(AFHTTPRequestOperation *, NSError *))failure;

@property (nonatomic, strong) NSFileManager *fileManager;
@property (nonatomic, strong) AFHTTPRequestOperation *currentMoveCopyDeleteOperation;

@end

@implementation DZWebDAVClient

@synthesize fileManager = _fileManager;

- (id)initWithBaseURL:(NSURL *)url {
    if ((self = [super initWithBaseURL:url])) {
		self.fileManager = [NSFileManager new];
        [self registerHTTPOperationClass: [DZDictionaryRequestOperation class]];
    }
    return self;
}

- (AFHTTPRequestOperation *)mr_operationWithRequest:(NSURLRequest *)request success:(void(^)(void))success failure:(void(^)(AFHTTPRequestOperation *, NSError *))failure {
	return [self HTTPRequestOperationWithRequest:request success:^(AFHTTPRequestOperation *operation, id responseObject) {
		if (success)
			success();
	} failure:failure];
}

- (NSMutableURLRequest *)requestWithMethod:(NSString *)method path:(NSString *)path parameters:(NSDictionary *)parameters {
    NSMutableURLRequest *request = [super requestWithMethod:method path:path parameters:parameters];
    [request setCachePolicy: NSURLRequestReloadIgnoringLocalCacheData];
    if ([method isEqualToString:@"COPY"]) {
        [request setTimeoutInterval:INT_MAX];
    }
    else {
        [request setTimeoutInterval: 300];
    }
    return request;
}

- (void)copyPath:(NSString *)source toPath:(NSString *)destination success:(void(^)(void))success failure:(void(^)(AFHTTPRequestOperation *, NSError *))failure {
    NSString *destinationPath = [[self.baseURL URLByAppendingPathComponent:destination] absoluteString];
    NSMutableURLRequest *request = [self requestWithMethod:@"COPY" path:source parameters:nil];
    [request setValue:destinationPath forHTTPHeaderField:@"Destination"];
	[request setValue:@"T" forHTTPHeaderField:@"Overwrite"];
	AFHTTPRequestOperation *operation = [self mr_operationWithRequest:request success:success failure:failure];
    [self enqueueHTTPRequestOperation:operation];
    self.currentMoveCopyDeleteOperation = operation;
}

- (void)movePath:(NSString *)source toPath:(NSString *)destination success:(void(^)(void))success failure:(void(^)(AFHTTPRequestOperation *, NSError *))failure {
    NSString *destinationPath = [[self.baseURL URLByAppendingPathComponent:destination] absoluteString];
    NSMutableURLRequest *request = [self requestWithMethod:@"MOVE" path:source parameters:nil];
    [request setValue:destinationPath forHTTPHeaderField:@"Destination"];
	[request setValue:@"T" forHTTPHeaderField:@"Overwrite"];
	AFHTTPRequestOperation *operation = [self mr_operationWithRequest:request success:success failure:failure];
    [self enqueueHTTPRequestOperation:operation];
    self.currentMoveCopyDeleteOperation = operation;
}

- (void)deletePath:(NSString *)path success:(void(^)(void))success failure:(void(^)(AFHTTPRequestOperation *, NSError *))failure {
    NSMutableURLRequest *request = [self requestWithMethod:@"DELETE" path:path parameters:nil];
	AFHTTPRequestOperation *operation = [self mr_operationWithRequest:request success:success failure:failure];
    [self enqueueHTTPRequestOperation:operation];
    self.currentMoveCopyDeleteOperation = operation;
}

- (void)getPath:(NSString *)remoteSource success:(void(^)(AFHTTPRequestOperation *, id))success failure:(void(^)(AFHTTPRequestOperation *, NSError *))failure {
	[self getPath: remoteSource parameters: nil success: success failure: failure];
}

- (void)getPaths:(NSArray *)remoteSources progressBlock:(void(^)(NSUInteger, NSUInteger))progressBlock completionBlock:(void(^)(NSArray *))completionBlock {
	NSMutableArray *requests = [NSMutableArray arrayWithCapacity: remoteSources.count];
	[remoteSources enumerateObjectsUsingBlock:^(NSString *remotePath, NSUInteger idx, BOOL *stop) {
		NSMutableURLRequest *request = [self requestWithMethod:@"GET" path:remotePath parameters:nil];
		[requests addObject:request];
	}];
	[self enqueueBatchOfHTTPRequestOperationsWithRequests:requests progressBlock:progressBlock completionBlock:completionBlock];
}

- (void)mr_listPath:(NSString *)path depth:(NSUInteger)depth success:(void(^)(AFHTTPRequestOperation *, id))success failure:(void(^)(AFHTTPRequestOperation *, NSError *))failure {
	NSParameterAssert(success);
	NSMutableURLRequest *request = [self requestWithMethod:@"PROPFIND" path:path parameters:nil];
	NSString *depthHeader = nil;
	if (depth <= 0)
		depthHeader = @"0";
	else if (depth == 1)
		depthHeader = @"1";
	else
		depthHeader = @"infinity";
    [request setValue: depthHeader forHTTPHeaderField: @"Depth"];
    NSMutableString *body = [@"<?xml version=\"1.0\" encoding=\"utf-8\" ?><D:propfind xmlns:D=\"DAV:\">" mutableCopy];
    if (depth == 0) {
        [body appendString:@"<D:prop><D:getcontenttype/><D:getlastmodified/><D:creationdate/><D:getcontentlength/></D:prop></D:propfind>"];
    }
    else {
        [body appendString:@"<D:prop><D:getcontenttype/><D:getlastmodified/><D:creationdate/><D:getcontentlength/></D:prop></D:propfind>"];
    }
    [request setHTTPBody:[body dataUsingEncoding:NSUTF8StringEncoding]];
    [request setValue:@"application/xml" forHTTPHeaderField:@"Content-Type"];
//    NSLog(@"REQUEST: %@", [request allHTTPHeaderFields]);
	AFHTTPRequestOperation *operation = [self HTTPRequestOperationWithRequest:request success:^(AFHTTPRequestOperation *operation, id responseObject) {
//        NSLog(@"RESPONSE OBJECT: %@", responseObject);
		if ((responseObject && ![responseObject isKindOfClass:[NSDictionary class]]) || nil == responseObject) {
            		if (failure)
                		failure(operation, [NSError errorWithDomain:AFNetworkingErrorDomain code:NSURLErrorCannotParseResponse userInfo:nil]);
            		return;
	        }
        
        id checkHrefs = [responseObject valueForKeyPath:@"multistatus.response.href"];

        NSMutableDictionary *unformattedDict = [NSMutableDictionary dictionaryWithCapacity:[checkHrefs isKindOfClass:[NSArray class]]?[checkHrefs count]:1];
        id response = [responseObject valueForKeyPath:@"multistatus.response"];
        NSArray *responseArray = [response isKindOfClass:[NSArray class]] ? response : @[response];
        for (id responseItem in responseArray) {
            if ([responseItem isKindOfClass:[NSDictionary class]]) {
                
                id propstat = [responseItem valueForKey:@"propstat"];
                if ([propstat isKindOfClass:[NSArray class]]) {
                    
                    //check status on properties
                    NSArray *propstats = [propstat isKindOfClass:[NSArray class]] ? propstat : @[propstat];
                    for(NSDictionary *propDict in propstats) {
                        
                        //Ignore not found properties
                        if ([[propDict valueForKey:@"status"] rangeOfString:@"404"].location == NSNotFound) {
                            [unformattedDict setObject:[propDict valueForKey:@"prop"] forKey:[responseItem valueForKey:@"href"]];
                            break;
                        }
                    }
                }
                else if([propstat isKindOfClass:[NSDictionary class]]){
                    NSDictionary *propDict = propstat;
                    [unformattedDict setObject:[propDict valueForKey:@"prop"] forKey:[responseItem valueForKey:@"href"]];
                }
            }
        }

		NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithCapacity: unformattedDict.count];
		
		[unformattedDict enumerateKeysAndObjectsUsingBlock:^(NSString *absoluteKey, NSDictionary *unformatted, BOOL *stop) {
			// filter out Finder thumbnail files (._filename), they get us screwed up.
			if ([absoluteKey.lastPathComponent hasPrefix: @"."])
				return;
			
			// Replace an absolute path with a relative one
			NSString *key = [absoluteKey stringByReplacingOccurrencesOfString:self.baseURL.path withString:@""];
			if ([[key substringToIndex:1] isEqualToString:@"/"])
				key = [key substringFromIndex:1];
			
			// reformat the response dictionaries into usable values
			NSMutableDictionary *object = [NSMutableDictionary dictionaryWithCapacity: 6];

            if ([unformatted isKindOfClass:[NSString class]]) {
                [object setObject:unformatted forKey:DZWebDAVContentTypeKey];
                [dict setObject: object forKey: key];
                return;
            }
            NSString *origCreationDate = [unformatted objectForKey: DZWebDAVCreationDateKey] ?: [unformatted objectForKey: @"creationdate"];;
            if (origCreationDate) {
                if ([origCreationDate isKindOfClass:[NSDictionary class]]) {
                    origCreationDate = [(NSDictionary *)origCreationDate objectForKey:@"text"];
                }
                NSDate *creationDate = [NSDate dateFromRFC1123String: origCreationDate] ?: [NSDate dateFromISO8601String: origCreationDate] ?: nil;
                if (creationDate) {
                    [object setObject: creationDate forKey: DZWebDAVCreationDateKey];
                }
            }
			
			NSString *origModificationDate = [unformatted objectForKey: DZWebDAVModificationDateKey] ?: [unformatted objectForKey: @"getlastmodified"];
            if (origModificationDate) {
                if ([origModificationDate isKindOfClass:[NSDictionary class]]) {
                    origModificationDate = [(NSDictionary *)origModificationDate objectForKey:@"text"];
                }
                NSDate *modificationDate = [NSDate dateFromRFC1123String: origModificationDate] ?: [NSDate dateFromISO8601String: origModificationDate] ?: nil;
                if (modificationDate) {
                    [object setObject: modificationDate forKey: DZWebDAVModificationDateKey];
                }
            }
            if ([unformatted objectForKey: DZWebDAVETagKey]) {
                [object setObject: [unformatted objectForKey: DZWebDAVETagKey] forKey: DZWebDAVETagKey];
            }
            if ([unformatted objectForKey: DZWebDAVCTagKey]) {
                [object setObject: [unformatted objectForKey: DZWebDAVCTagKey] forKey: DZWebDAVCTagKey];
            }
            if ([unformatted objectForKey: DZWebDAVResourceTypeKey]) {
                [object setObject: [unformatted objectForKey: DZWebDAVResourceTypeKey] forKey: DZWebDAVResourceTypeKey];
            }
            if ([unformatted objectForKey: DZWebDAVContentTypeKey] || [unformatted objectForKey: @"contenttype"]) {
                [object setObject: [unformatted objectForKey: DZWebDAVContentTypeKey] ?: [unformatted objectForKey: @"contenttype"] forKey: DZWebDAVContentTypeKey];
            }
            NSNumber *contentLength = [unformatted objectForKey: DZWebDAVContentLengthKey] ?: [unformatted objectForKey: @"getcontentlength"];
            if (contentLength) {
                [object setObject:contentLength forKey: DZWebDAVContentLengthKey];
            }
			
			[dict setObject: object forKey: key];
		}];
		
		if (success)
			success(operation, dict);
	} failure:failure];
	[self enqueueHTTPRequestOperation:operation];
}

- (void)propertiesOfPath:(NSString *)path success:(void(^)(AFHTTPRequestOperation *, id ))success failure:(void(^)(AFHTTPRequestOperation *, NSError *))failure {
	[self mr_listPath:path depth:0 success:success failure:failure];
}

- (void)listPath:(NSString *)path success:(void(^)(AFHTTPRequestOperation *, id))success failure:(void(^)(AFHTTPRequestOperation *, NSError *))failure {
	[self mr_listPath:path depth:1 success:success failure:failure];
}

- (void)recursiveListPath:(NSString *)path success:(void(^)(AFHTTPRequestOperation *, id))success failure:(void(^)(AFHTTPRequestOperation *, NSError *))failure {
	[self mr_listPath:path depth:2 success:success failure:failure];
}

- (void)downloadPath:(NSString *)remoteSource toURL:(NSURL *)localDestination success:(void(^)(void))success failure:(void(^)(AFHTTPRequestOperation *, NSError *))failure {
	if ([self.fileManager respondsToSelector:@selector(createDirectoryAtURL:withIntermediateDirectories:attributes:error:) ]) {
		[self.fileManager createDirectoryAtURL: [localDestination URLByDeletingLastPathComponent] withIntermediateDirectories: YES attributes: nil error: NULL];
	} else {
		[self.fileManager createDirectoryAtPath: [localDestination.path stringByDeletingLastPathComponent] withIntermediateDirectories: YES attributes: nil error: NULL];
	}
	NSMutableURLRequest *request = [self requestWithMethod:@"GET" path:remoteSource parameters:nil];
	AFHTTPRequestOperation *operation = [self mr_operationWithRequest:request success:success failure:failure];
	operation.outputStream = [NSOutputStream outputStreamWithURL: localDestination append: NO];
    [self enqueueHTTPRequestOperation:operation];
    self.currentMoveCopyDeleteOperation = operation;
}

- (void)downloadPaths:(NSArray *)remoteSources toURL:(NSURL *)localFolder progressBlock:(void(^)(NSUInteger, NSUInteger))progressBlock completionBlock:(void(^)(NSArray *))completionBlock {
	BOOL hasURL = YES;
	if ([self.fileManager respondsToSelector:@selector(createDirectoryAtURL:withIntermediateDirectories:attributes:error:)]) {
		[self.fileManager createDirectoryAtURL: localFolder withIntermediateDirectories: YES attributes: nil error: NULL];
	} else {
		[self.fileManager createDirectoryAtPath: localFolder.path withIntermediateDirectories: YES attributes: nil error: NULL];
		hasURL = NO;
	}
	NSMutableArray *operations = [NSMutableArray arrayWithCapacity: remoteSources.count];
	[remoteSources enumerateObjectsUsingBlock:^(NSString *remotePath, NSUInteger idx, BOOL *stop) {
		NSURL *localDestination = hasURL ? [localFolder URLByAppendingPathComponent: remotePath isDirectory: [remotePath hasSuffix:@"/"]] : [NSURL URLWithString: remotePath relativeToURL: localFolder];
		NSMutableURLRequest *request = [self requestWithMethod:@"GET" path:remotePath parameters:nil];
		AFHTTPRequestOperation *operation = [self HTTPRequestOperationWithRequest:request success:NULL failure:NULL];
		operation.outputStream = [NSOutputStream outputStreamWithURL:localDestination append:NO];
		[operations addObject:operation];
	}];
	[self enqueueBatchOfHTTPRequestOperations:operations progressBlock:progressBlock completionBlock:completionBlock];
}

- (void)makeCollection:(NSString *)path success:(void(^)(void))success failure:(void(^)(AFHTTPRequestOperation *, NSError *))failure {
	NSURLRequest *request = [self requestWithMethod:@"MKCOL" path:path parameters:nil];	
	AFHTTPRequestOperation *operation = [self mr_operationWithRequest:request success:success failure:failure];
    [self enqueueHTTPRequestOperation:operation];
    self.currentMoveCopyDeleteOperation = operation;
}

- (void)put:(NSData *)data path:(NSString *)remoteDestination success:(void(^)(void))success failure:(void(^)(AFHTTPRequestOperation *, NSError *))failure {
    NSMutableURLRequest *request = [self requestWithMethod:@"PUT" path:remoteDestination parameters:nil];
	[request setValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"];
	[request setValue:[NSString stringWithFormat:@"%ld", (long)data.length] forHTTPHeaderField:@"Content-Length"];
	AFHTTPRequestOperation *operation = [self mr_operationWithRequest:request success:success failure:failure];
	operation.inputStream = [NSInputStream inputStreamWithData:data];
    [self enqueueHTTPRequestOperation:operation];
    self.currentMoveCopyDeleteOperation = operation;
}

- (void)putLocalPath:(NSString *)localSource path:(NSString *)remoteDestination success:(void(^)(void))success failure:(void(^)(AFHTTPRequestOperation *, NSError *))failure {
    NSMutableURLRequest *request = [self requestWithMethod:@"PUT" path:remoteDestination parameters:nil];
	[request setValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"];
    NSUInteger fileSize = [[[[NSFileManager defaultManager] attributesOfItemAtPath:localSource error:nil] objectForKey:NSFileSize] unsignedIntegerValue];
    [request setValue:[NSString stringWithFormat:@"%u", fileSize] forHTTPHeaderField:@"Content-Length"];
	AFHTTPRequestOperation *operation = [self mr_operationWithRequest:request success:success failure:failure];
	operation.inputStream = [NSInputStream inputStreamWithFileAtPath:localSource];
    [self enqueueHTTPRequestOperation:operation];
    self.currentMoveCopyDeleteOperation = operation;
}

- (void)putURL:(NSURL *)localSource path:(NSString *)remoteDestination success:(void(^)(void))success failure:(void(^)(AFHTTPRequestOperation *, NSError *))failure {
    NSMutableURLRequest *request = [self requestWithMethod:@"PUT" path:remoteDestination parameters:nil];
	[request setValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"];
	AFHTTPRequestOperation *operation = [self mr_operationWithRequest:request success:success failure:failure];
	operation.inputStream = [NSInputStream inputStreamWithURL:localSource];
    [self enqueueHTTPRequestOperation:operation];
}

- (void)lockPath:(NSString *)path exclusive:(BOOL)exclusive recursive:(BOOL)recursive timeout:(NSTimeInterval)timeout success:(void(^)(AFHTTPRequestOperation *operation, DZWebDAVLock *lock))success failure:(void(^)(AFHTTPRequestOperation *operation, NSError *error))failure {
    NSParameterAssert(success);
    NSMutableURLRequest *request = [self requestWithMethod: @"LOCK" path: path parameters: nil];
    [request setValue: @"application/xml" forHTTPHeaderField: @"Content-Type"];
    [request setValue: timeout ? [NSString stringWithFormat: @"Second-%f", timeout] : @"Infinite, Second-4100000000" forHTTPHeaderField: @"Timeout"];
	[request setValue: recursive ? @"Infinity" : @"0" forHTTPHeaderField: @"Depth"];
    NSString *bodyData = [NSString stringWithFormat: @"<?xml version=\"1.0\" encoding=\"utf-8\"?><D:lockinfo xmlns:D=\"DAV:\"><D:lockscope><D:%@/></D:lockscope><D:locktype><D:write/></D:locktype></D:lockinfo>", exclusive ? @"exclusive" : @"shared"];
    [request setHTTPBody: [bodyData dataUsingEncoding:NSUTF8StringEncoding]];
    AFHTTPRequestOperation *operation = [self HTTPRequestOperationWithRequest: request success:^(AFHTTPRequestOperation *operation, id responseObject) {
        success(operation, [[DZWebDAVLock alloc] initWithURL: operation.request.URL responseObject: responseObject]);
    } failure: failure];
    [self enqueueHTTPRequestOperation: operation];
}

- (void)refreshLock:(DZWebDAVLock *)lock success:(void(^)(AFHTTPRequestOperation *operation, DZWebDAVLock *lock))success failure:(void(^)(AFHTTPRequestOperation *operation, NSError *error))failure {
    NSMutableURLRequest *request = [self requestWithMethod: @"LOCK" path: lock.URL.path parameters: nil];
    [request setValue: [NSString stringWithFormat:@"(<%@>)", lock.token] forHTTPHeaderField: @"If"];
    [request setValue: lock.timeout ? [NSString stringWithFormat: @"Second-%f", lock.timeout] : @"Infinite, Second-4100000000" forHTTPHeaderField: @"Timeout"];
	[request setValue: lock.recursive ? @"Infinity" : @"0" forHTTPHeaderField: @"Depth"];
    AFHTTPRequestOperation *operation = [self HTTPRequestOperationWithRequest: request success:^(AFHTTPRequestOperation *operation, id responseObject) {
        [lock updateFromResponseObject: responseObject];
        success(operation, lock);
    } failure: failure];
    [self enqueueHTTPRequestOperation: operation];
}

- (void)unlock:(DZWebDAVLock *)lock success:(void(^)(void))success failure:(void(^)(AFHTTPRequestOperation *operation, NSError *error))failure {
    NSMutableURLRequest *request = [self requestWithMethod: @"UNLOCK" path: lock.URL.path parameters: nil];
	[request setValue:@"application/xml" forHTTPHeaderField:@"Content-Type"];
	[request setValue:[NSString stringWithFormat:@"<%@>", lock.token] forHTTPHeaderField:@"Lock-Token"];
    AFHTTPRequestOperation *operation = [self mr_operationWithRequest:request success:success failure:failure];
    [self enqueueHTTPRequestOperation:operation];
}

- (void)cancelCurrentMoveCopyDeleteOperation
{
    [self.currentMoveCopyDeleteOperation cancel];
}

@end
