import java.util.concurrent.Callable
import java.util.concurrent.Executors

class Main {
    companion object {
        private val pool = Executors.newFixedThreadPool(Runtime.getRuntime().availableProcessors())
        private data class ThreadingProcContext(
            var elements: LongArray? = null,
            var elementsSize: Long = 0,
            var workerIndex: Int = 0,
            var totalWorkers: Int = 1
        )

        private fun runWave(context: ThreadingProcContext) {
            var i = context.workerIndex
            while (i < context.elementsSize / 2) {
                val oppositeIndex = (context.elementsSize - 1 - i).toInt()
                synchronized(context.elements!!) {
                    val current = context.elements!![i]
                    val opposite = context.elements!![oppositeIndex]
                    context.elements!![i] = current + opposite
                }
                i += context.totalWorkers
            }
        }

        private fun printArray(elements: LongArray) {
            for (i in elements.indices) {
                print("${elements[i]} ")
            }
            println()
        }

        private fun solveMulticore(elements: LongArray, numThreads: Int) {
            var elementsSize = elements.size.toLong()
            while (elementsSize > 1) {
                val tasks = ArrayList<Callable<Void>>()
                repeat(numThreads) { i ->
                    tasks.add(Callable<Void> {
                        runWave(ThreadingProcContext(elements, elementsSize, i, numThreads))
                        return@Callable null
                    })
                }
                pool.invokeAll(tasks)
                elementsSize = (elementsSize + 1) / 2
                printArray(elements)
            }
        }

        private fun shutdown() {
            pool.shutdown()
            try {
                if (!pool.awaitTermination(60, java.util.concurrent.TimeUnit.SECONDS)) {
                    pool.shutdownNow()
                    if (!pool.awaitTermination(60, java.util.concurrent.TimeUnit.SECONDS)) {
                        println("Пул потоків не вдалося завершити роботу")
                    }
                }
            } catch (e: InterruptedException) {
                pool.shutdownNow()
                Thread.currentThread().interrupt()
            }
        }

        @JvmStatic
        fun main(args: Array<String>) {
            val elementsSize = 1000
            val numThreads = 5
            val elements = LongArray(elementsSize) { it.toLong() + 1 }
            println("Початковий масив: ")
            printArray(elements)
            val startTime = System.currentTimeMillis()
            println("Обчислення за допомогою кількох потоків:")
            solveMulticore(elements, numThreads)
            val endTime = System.currentTimeMillis()
            val milliseconds = (endTime - startTime)
            println("Обчислення зайняло $milliseconds мілісекунд")
            println("Результат після обчислення: ${elements[0]}")
            shutdown()
        }
    }
}

