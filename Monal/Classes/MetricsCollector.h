//
//  MetricsCollector.h
//  Monal
//
//  isaCloud: coleta de métricas do aparelho, por build, para avaliação de
//  consumo (memória, CPU, bateria/térmica, tamanho do banco) e das métricas
//  oficiais do sistema (MetricKit). Tudo fica em arquivos JSON dentro do
//  container do App Group e é exportado pelo Depuração.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MetricsCollector : NSObject

/// starts the sampling (idempotent): MetricKit subscriber, notifications and the periodic timer
+(void) start;

/// writes one sample now (also used by the notification handlers)
+(void) sampleNow;

/// builds a single JSON with every sample and MetricKit payload collected so far, for the share sheet
+(NSURL* _Nullable) exportMetrics;

/// directory where the samples and the MetricKit payloads live
+(NSString*) metricsDirectoryPath;

@end

NS_ASSUME_NONNULL_END
